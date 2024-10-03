// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "./../interfaces/IPo.sol";
import "./../interfaces/IStaking.sol";
import "./../interfaces/IGovernorExecution.sol";
import "./../interfaces/IGovernorGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title GovernorOperations
 * @dev Implements DAO governance functionalities including proposing, voting, and executing proposals.
 * It integrates with external contracts for staking validation, participation and proposal execution.
 */
contract GovernorOperations is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;
    using SignatureChecker for bytes32;

    // *** ERRORS *** //
    error CannotBeZeroAddress();
    error CannotExecute();
    error CannotVoteOnQVProposals();
    error ExecutableProposalsCannotBeCompleted();
    error ProposalInexistent();
    error IncorrectPhase(ProposalStatus);
    error InvalidInput();
    error VoteChangeNotAllowedAfterCutOff();
    error VoteChangeWindowExpired();
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error ProposalLifeTimePassed();
    error ProposeLock();
    error ProposalOngoing(
        uint256 id,
        uint256 currentTimestamp,
        uint256 proposalEndTimestamp
    );
    error ProposalNotPassed();
    error QuorumNotReached(uint256 id, uint256 totalVotes, uint256 quorum);
    error Unauthorized(address caller);

    ///*** STRUCTS ***///
    struct Proposal {
        string info;
        uint256 startBlockNum;
        uint256 endTimestamp;
        ProposalStatus status;
        address action;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 totalVotes;
        bool executable;
        bool quadraticVoting;
    }

    struct UserVoteData {
        bool voted; // Whether the user has voted
        uint256 initialVoteTimestamp; // The timestamp of when the user first voted
        bool previousSupport; // Whether the user supported the last vote
        uint256 previousVoteAmount; // The amount of votes cast in the last vote
    }

    ///*** INTERFACES ***///
    IPo private po;
    IGovernorExecution private govExec;
    IGovernorGuard private govGuard;

    ///*** GOVERNANCE PARAMETERS ***///
    uint256 public proposalLifeTime;
    uint256 public quorum;
    uint256 public proposeLockTime;
    uint256 public voteLockTime;
    uint256 public voteChangeTime;
    uint256 public voteChangeCutOff;
    uint256 public opThreshold;
    uint256 public maxVotingStreak;

    ///*** KEY ADDRESSES ***///
    address public stakingAddress;
    address public admin;
    address private signer;

    ///*** STORAGE & MAPPINGS ***///
    uint256 private _index;
    mapping(uint256 => Proposal) private proposals;
    mapping(address => uint256) private votingStreak;
    mapping(address => mapping(uint256 => UserVoteData)) private userVoteData;

    ///*** ROLES ***///
    bytes32 public constant GUARD_ROLE = keccak256("GUARD_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    ///*** ENUMERATORS ***///

    /**
     * @notice Enumerates the different states a proposal can be in.
     */
    enum ProposalStatus {
        Active,
        Scheduled,
        Executed,
        Completed, //Completed status only for proposals that cannot be executed
        Cancelled
    }

    ///*** MODIFIER ***///

    /**
     * @dev Modifier to check if the caller has the `EXECUTOR_ROLE` in `GovernorExecutor`.
     */
    modifier onlyExecutor() {
        if (!govExec.hasRole(EXECUTOR_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /*** EVENTS ***/
    event Cancelled(uint256 indexed id, bool indexed rejected);
    event Completed(uint256 indexed id);
    event EmergencyCancel(uint256 indexed id, string reason);
    event Executed(
        uint256 indexed id,
        address indexed govExec,
        address indexed action
    );

    event Proposed(
        uint256 indexed id,
        address indexed govExec,
        address indexed action
    );

    event SetGovParam(bytes32 param, uint256 data);

    event SetNewGovExecAddress(
        address indexed user,
        address indexed newAddress
    );

    event SetNewGovGuardAddress(
        address indexed user,
        address indexed newAddress
    );

    event SetNewMaxVotingStreak(
        address indexed user,
        uint256 newMaxVotingStreak
    );

    event SetNewPoToken(address indexed user, address poToken);
    event SetNewStakingAddress(
        address indexed user,
        address indexed newAddress
    );

    event SetNewSignerAddress(address indexed user, address indexed newAddress);
    event SetNewAdmin(address indexed user, address indexed newAddress);
    event Scheduled(uint256 indexed id);
    event Voted(
        uint256 indexed id,
        address indexed user,
        bool indexed support,
        uint256 amount
    );

    constructor(
        address stakingAddress_,
        address admin_,
        address po_,
        address signer_
    ) {
        if (
            stakingAddress_ == address(0) ||
            admin_ == address(0) ||
            po_ == address(0) ||
            signer_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }
        stakingAddress = stakingAddress_;
        admin = admin_;
        po = IPo(po_);
        signer = signer_;

        opThreshold = 5000e18;
        maxVotingStreak = 5;
        proposalLifeTime = 4 weeks;
        quorum = 567300e18; // 3% of circulating supply of 18.91 million SCI
        voteLockTime = 1 weeks;
        proposeLockTime = 1 weeks;
        voteChangeTime = 1 hours;
        voteChangeCutOff = 3 days;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev Updates the admin address and transfers admin role.
     * @param newAdmin The address to be set as the new admin.
     */
    function setAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldAdmin = admin;
        admin = newAdmin;
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        emit SetNewAdmin(oldAdmin, newAdmin);
    }

    /**
     * @dev sets the staking address
     */
    function setStakingAddress(
        address newStakingAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingAddress = newStakingAddress;
        emit SetNewStakingAddress(msg.sender, newStakingAddress);
    }

    /**
     * @dev sets the GovernorExecution address
     */
    function setGovExec(
        address newGovernorAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govExec = IGovernorExecution(newGovernorAddress);
        emit SetNewGovExecAddress(msg.sender, newGovernorAddress);
    }

    /**
     * @dev sets the GovernorGuard address
     */
    function setGovGuard(
        address newGovGuardAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govGuard = IGovernorGuard(newGovGuardAddress);
        _grantRole(GUARD_ROLE, newGovGuardAddress);
        emit SetNewGovGuardAddress(msg.sender, newGovGuardAddress);
    }

    /**
     * @dev sets the signer address
     */
    function setSigner(
        address newSigner
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = newSigner;
        emit SetNewSignerAddress(msg.sender, newSigner);
    }

    /**
     * @dev sets the PO token address and interface
     */
    function setPoToken(address po_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        po = IPo(po_);
        emit SetNewPoToken(msg.sender, po_);
    }

    /**
     * @dev sets the governance parameters given data
     * @param param the parameter of interest
     * @param data the data assigned to the parameter
     */
    function setGovParams(bytes32 param, uint256 data) external onlyExecutor {
        //the duration of the proposal
        if (param == "proposalLifeTime") proposalLifeTime = data;

        //provide a percentage of the total supply
        if (param == "quorum") quorum = data;

        //the lock time of your tokens after voting
        if (param == "voteLockTime") voteLockTime = data;

        //the lock time of your tokens and ability to propose after proposing
        if (param == "proposeLockTime") proposeLockTime = data;

        //the time for a user to change their vote after their initial vote
        if (param == "voteChangeTime") voteChangeTime = data;

        //the time before the end of the proposal that users can change their votes
        if (param == "voteChangeCutOff") voteChangeCutOff = data;

        //the max voting streak indirectly affecting the number of PO tokens users can receive
        if (param == "maxVotingStreak") maxVotingStreak = data;

        //the number of tokens the user must have staked to propose
        if (param == "opThreshold") opThreshold = data;

        emit SetGovParam(param, data);
    }

    /**
     * @dev Proposes a change in DAO operations. At least one option needs to be proposed.
     * @param info IPFS hash of project proposal.
     * @param quadraticVoting Whether quadratic voting is enabled for the proposal.
     * @return uint256 Index of the newly created proposal.
     */
    function propose(
        string memory info,
        address action,
        bool quadraticVoting
    ) external nonReentrant returns (uint256) {
        if (bytes(info).length == 0) revert InvalidInput();

        bool executable;

        if (action == address(0)) {
            executable = false;
        } else {
            executable = true;
        }

        IStaking staking = IStaking(stakingAddress);

        _validateStakingRequirements(staking, msg.sender);

        uint256 currentIndex = _storeProposal(
            info,
            action,
            quadraticVoting,
            executable,
            staking
        );

        emit Proposed(currentIndex, address(govExec), action);

        return currentIndex;
    }

    /**
     * @dev vote for an option of a given proposal
     *      using the rights from the most recent snapshot
     * @param id the _index of the proposal
     * @param support user's choice to support a proposal or not
     */
    function voteStandard(uint id, bool support) external nonReentrant {
        _votingChecks(id, msg.sender);

        if (proposals[id].quadraticVoting) revert CannotVoteOnQVProposals();

        uint256 votingRights = IStaking(stakingAddress).getLatestUserRights(
            msg.sender
        );

        _recordVote(id, support, votingRights);
    }

    function voteQV(
        uint id,
        bool support,
        bool isUnique,
        bytes memory signature
    ) external nonReentrant {
        _votingChecks(id, msg.sender);
        _uniquenessCheck(id, msg.sender, isUnique, signature);

        uint256 votingRights = IStaking(stakingAddress).getLatestUserRights(
            msg.sender
        );

        uint256 actualVotes = Math.sqrt(votingRights / 10 ** 18) * 10 ** 18;

        _recordVote(id, support, actualVotes);
    }

    /**
     * @dev schedules the the execution or completion of a proposal
     * @param id the _index of the proposal of interest
     */
    function schedule(uint256 id) external nonReentrant {
        if (id >= _index) revert ProposalInexistent();

        if (block.timestamp < proposals[id].endTimestamp)
            revert ProposalOngoing(
                id,
                block.timestamp,
                proposals[id].endTimestamp
            );

        bool schedulable = _proposalSchedulingChecks(id, true);

        if (schedulable) {
            if (proposals[id].executable) {
                govExec.schedule(proposals[id].action);
            }
            proposals[id].status = ProposalStatus.Scheduled;

            emit Scheduled(id);
        }
    }

    /**
     * @dev executes the proposal using a token or coin - Operation's crew's choice
     * @param id the _index of the proposal of interest
     */
    /**
     * @dev Executes a scheduled proposal by temporarily assigning the EXECUTOR_ROLE to the target action,
     * executing the action, and then removing the role. Reverts if conditions for execution are not met.
     * @param id The ID of the proposal to be executed.
     */
    function execute(uint256 id) external payable nonReentrant {
        if (id >= _index) revert ProposalInexistent();

        if (proposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(proposals[id].status);

        if (!proposals[id].executable) revert CannotExecute();

        address[] memory governor = new address[](1);
        governor[0] = address(proposals[id].action);

        govExec.execution(proposals[id].action);

        proposals[id].status = ProposalStatus.Executed;

        emit Executed(id, address(govExec), proposals[id].action);
    }

    /**
     * @dev completes off-chain execution proposals
     * @param id the _index of the proposal of interest
     */
    function complete(uint256 id) external nonReentrant {
        if (id > _index) revert ProposalInexistent();

        if (proposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(proposals[id].status);

        if (proposals[id].executable) {
            revert ExecutableProposalsCannotBeCompleted();
        }

        proposals[id].status = ProposalStatus.Completed;

        emit Completed(id);
    }

    /**
     * @dev cancels the proposal
     * @param id the _index of the proposal of interest
     */
    function cancel(uint256 id) external nonReentrant onlyRole(GUARD_ROLE) {
        if (proposals[id].status == ProposalStatus.Executed)
            revert IncorrectPhase(proposals[id].status);

        if (proposals[id].executable) govExec.cancel(proposals[id].action);

        proposals[id].status = ProposalStatus.Cancelled;

        emit Cancelled(id, false);
    }

    /**
     * @dev cancels the proposal
     * @param id the _index of the proposal of interest
     */
    function cancelRejected(uint256 id) external nonReentrant {
        if (id >= _index) revert ProposalInexistent();

        bool schedulable = _proposalSchedulingChecks(id, false);

        if (!schedulable) {
            proposals[id].status = ProposalStatus.Cancelled;

            emit Cancelled(id, true);
        }
    }

    /**
     * @dev returns the PO token address
     */
    function getPoToken() external view returns (address) {
        return address(po);
    }

    /**
     * @dev returns the operations proposal _index
     */
    function getProposalIndex() external view returns (uint256) {
        return _index;
    }

    /**
     * @dev returns the signer address
     */
    function getSigner()
        external
        view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (address)
    {
        return signer;
    }

    /**
     * @dev Retrieves the current governance parameters.
     * @return proposalLifeTime The lifetime of a proposal from its creation to its completion.
     * @return quorum The percentage of votes required for a proposal to be considered valid.
     * @return voteLockTime The duration for which voting on a proposal is open.
     * @return proposeLockTime The lock time before which a new proposal cannot be made.
     * @return voteChangeTime The time window during which a vote can be changed after the initial vote.
     * @return voteChangeCutOff The time before the end of the proposal during which vote changes are no longer allowed.
     */
    function getGovernanceParameters()
        public
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return (
            proposalLifeTime,
            quorum,
            voteLockTime,
            proposeLockTime,
            voteChangeTime,
            voteChangeCutOff,
            opThreshold
        );
    }

    /**
     * @notice Retrieves voting data for a specific user on a specific proposal.
     * @dev This function returns the user's voting data for a proposal identified by its unique ID. It ensures the proposal exists before fetching the data.
     *      If the proposal ID is invalid (greater than the current maximum index), it reverts with `ProposalInexistent`.
     * @param user The address of the user whose voting data is being requested.
     * @param id The unique identifier (index) of the proposal for which the user's voting data is being requested. This ID is sequentially assigned to proposals as they are created.
     */
    function getUserVoteData(
        address user,
        uint256 id
    ) external view returns (UserVoteData memory) {
        if (id > _index) revert ProposalInexistent();
        return
            UserVoteData(
                userVoteData[user][id].voted,
                userVoteData[user][id].initialVoteTimestamp,
                userVoteData[user][id].previousSupport,
                userVoteData[user][id].previousVoteAmount
            );
    }

    /**
     * @notice Retrieves detailed information about a specific governance proposal.
     * @dev This function returns comprehensive details of a proposal identified by its unique ID. It ensures the proposal exists before fetching the details. If the proposal ID is invalid (greater than the current maximum index), it reverts with `ProposalInexistent`.
     * @param id The unique identifier (index) of the proposal whose information is being requested. This ID is sequentially assigned to proposals as they are created.
     */
    function getProposalInfo(
        uint256 id
    ) external view returns (Proposal memory) {
        if (id > _index) revert ProposalInexistent();

        // Return a struct with the proposal details
        return
            Proposal(
                proposals[id].info,
                proposals[id].startBlockNum,
                proposals[id].endTimestamp,
                proposals[id].status,
                proposals[id].action,
                proposals[id].votesFor,
                proposals[id].votesAgainst,
                proposals[id].totalVotes,
                proposals[id].executable,
                proposals[id].quadraticVoting
            );
    }

    ///*** INTERNAL FUNCTIONS ***///

    /**
     * @dev Internal function that performs checks to determine if a proposal can be scheduled.
     *      - Checks include proposal status, quorum requirements, and vote tally.
     *      - Optionally reverts with specific errors if `revertable` is set to true.
     * @param id The unique identifier of the proposal.
     * @param revertable If true, reverts with an error if any check fails.
     * @return passed A boolean value indicating whether all the checks are passed.
     */
    function _proposalSchedulingChecks(
        uint256 id,
        bool revertable
    ) internal view returns (bool) {
        uint256 sqrtQuorum = Math.sqrt(quorum / 10 ** 18) * 10 ** 18;

        bool isProposalOngoing = block.timestamp < proposals[id].endTimestamp;

        bool isProposalActive = proposals[id].status == ProposalStatus.Active;

        bool quorumReached = proposals[id].quadraticVoting
            ? proposals[id].totalVotes >= sqrtQuorum
            : proposals[id].totalVotes >= quorum;

        bool isVotesForGreaterThanVotesAgainst = proposals[id].votesFor >
            proposals[id].votesAgainst;

        bool passed = !isProposalOngoing &&
            isProposalActive &&
            quorumReached &&
            isVotesForGreaterThanVotesAgainst;

        if (!passed && revertable) {
            if (isProposalOngoing) {
                revert ProposalOngoing(
                    id,
                    block.timestamp,
                    proposals[id].endTimestamp
                );
            }
            if (!isProposalActive) {
                revert IncorrectPhase(proposals[id].status);
            }
            if (!quorumReached) {
                revert QuorumNotReached(
                    id,
                    proposals[id].totalVotes,
                    proposals[id].quadraticVoting ? sqrtQuorum : quorum
                );
            }
            if (!isVotesForGreaterThanVotesAgainst) {
                revert ProposalNotPassed();
            }
        }

        return passed;
    }

    /**
     * @dev Performs validation checks for quadratic voting actions.
     *      This function validates the presence of Holonym's SBT in the user's account
     *      to ensure the account is unique.
     *
     * @param id The index of the proposal on which to vote.
     * @param isUnique The status of the uniqueness of the account casting the vote.
     * @param signature The signature of the data related to the account's uniqueness.
     *
     *
     */
    function _uniquenessCheck(
        uint256 id,
        address user,
        bool isUnique,
        bytes memory signature
    ) internal view {
        if (proposals[id].quadraticVoting) {
            bool verified = _verify(user, isUnique, signature);
            require(verified, "Invalid signature");
            require(isUnique, "User does not have a valid SBT");
        }
    }

    /**
     * @dev Calculates a keccak256 hash for the given parameters.
     * @param user The user's Ethereum address.
     * @param isUnique Boolean flag representing whether the user's status is unique.
     * @return The calculated keccak256 hash.
     */
    function _getMessageHash(
        address user,
        bool isUnique
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, isUnique));
    }

    /**
     * @dev Verifies if a given signature is valid for the specified user and uniqueness.
     * @param user The address of the user to verify.
     * @param isUnique Boolean flag to check along with the user address.
     * @param signature The signature to verify.
     * @return True if the signature is valid, false otherwise.
     */
    function _verify(
        address user,
        bool isUnique,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 messageHash = _getMessageHash(user, isUnique);
        bytes32 ethSignedMessageHash = ECDSA.toEthSignedMessageHash(
            messageHash
        );

        return
            SignatureChecker.isValidSignatureNow(
                signer,
                ethSignedMessageHash,
                signature
            );
    }

    /**
     * @dev Performs common validation checks for all voting actions.
     *      This function validates the existence and status of a proposal, ensures that voting
     *      conditions such as proposal activity and timing constraints are met, and verifies
     *      the signature of the voter where necessary.
     *
     * @param id The index of the proposal on which to vote.
     * @param voter the user that wants to vote on the given proposal id
     *
     *
     */
    function _votingChecks(uint id, address voter) internal view {
        // Common proposal-related checks
        if (id >= _index) revert ProposalInexistent();
        if (proposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(proposals[id].status);
        if (block.timestamp > proposals[id].endTimestamp)
            revert ProposalLifeTimePassed();
        if (
            userVoteData[voter][id].voted &&
            block.timestamp >= proposals[id].endTimestamp - voteChangeCutOff
        ) revert VoteChangeNotAllowedAfterCutOff();
        if (
            userVoteData[voter][id].voted &&
            block.timestamp >
            userVoteData[voter][id].initialVoteTimestamp + voteChangeTime
        ) {
            revert VoteChangeWindowExpired();
        }
    }

    /**
     * @dev Records a vote on a proposal, updating the vote totals and voter status.
     *      This function is called after all preconditions checked by `_votingChecks` are met.
     *
     * @param id The index of the proposal on which to vote.
     * @param support A boolean indicating whether the vote is in support of (true) or against (false) the proposal.
     * @param actualVotes The effective number of votes to record, which may be adjusted for voting type, such as quadratic.
     */
    function _recordVote(uint id, bool support, uint actualVotes) internal {
        UserVoteData storage voteData = userVoteData[msg.sender][id];

        if (voteData.voted) {
            if (voteData.previousSupport) {
                proposals[id].votesFor -= voteData.previousVoteAmount;
            } else {
                proposals[id].votesAgainst -= voteData.previousVoteAmount;
            }
            proposals[id].totalVotes -= voteData.previousVoteAmount;
        }

        if (support) {
            proposals[id].votesFor += actualVotes;
        } else {
            proposals[id].votesAgainst += actualVotes;
        }
        proposals[id].totalVotes += actualVotes;

        if (!voteData.voted) {
            if (id > 0 && userVoteData[msg.sender][id - 1].voted) {
                votingStreak[msg.sender] = votingStreak[msg.sender] >=
                    maxVotingStreak
                    ? maxVotingStreak
                    : votingStreak[msg.sender] + 1;
            } else {
                votingStreak[msg.sender] = 1;
            }
            po.mint(msg.sender, votingStreak[msg.sender]);
        }

        voteData.voted = true;
        voteData.previousSupport = support;
        voteData.previousVoteAmount = actualVotes;

        if (voteData.initialVoteTimestamp == 0) {
            voteData.initialVoteTimestamp = block.timestamp;
        }

        IStaking(stakingAddress).voted(
            msg.sender,
            block.timestamp + voteLockTime
        );

        emit Voted(id, msg.sender, support, actualVotes);
    }

    /**
     * @dev Checks if the proposer satisfies the staking requirements for proposal submission.
     * @param staking The staking contract interface to check staked amounts.
     * @param proposer Address of the user making the proposal.
     *
     * @notice Reverts with InsufficientBalance if the staked amount is below the required threshold.
     * Reverts with ProposeLock if the proposer's tokens are locked due to a recent proposal.
     */
    function _validateStakingRequirements(
        IStaking staking,
        address proposer
    ) internal view {
        if (staking.getStakedSci(proposer) < opThreshold)
            revert InsufficientBalance(
                staking.getStakedSci(proposer),
                opThreshold
            );

        if (staking.getProposeLockEnd(proposer) > block.timestamp)
            revert ProposeLock();
    }

    /**
     * @dev Stores a new operation proposal in the contract's state and updates staking.
     * @param action contract address executing an action.
     * @param quadraticVoting Boolean indicating if quadratic voting is enabled for this proposal.
     * @param staking The staking contract interface used for updating the proposer's status.
     * @return uint256 The _index where the new proposal is stored.
     *
     * @notice The function increments the operations proposal _index after storing.
     * It also updates the staking contract to reflect the new proposal.
     */
    function _storeProposal(
        string memory info,
        address action,
        bool quadraticVoting,
        bool executable,
        IStaking staking
    ) internal returns (uint256) {
        Proposal memory proposal = Proposal(
            info,
            block.number,
            block.timestamp + proposalLifeTime,
            ProposalStatus.Active,
            action,
            0,
            0,
            0,
            executable,
            quadraticVoting
        );

        uint256 currentIndex = _index++;
        proposals[currentIndex] = proposal;

        staking.proposed(msg.sender, block.timestamp + proposeLockTime);

        return currentIndex;
    }
}
