// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "./../interfaces/IPo.sol";
import "./../interfaces/ISciManager.sol";
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
 * It integrates with external contracts for sciManager validation, participation and proposal execution.
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
    error InvalidGovernanceParameter();
    error VoteChangeNotAllowedAfterCutOff();
    error VoteChangeWindowExpired();
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error ProposalNotCancelable();
    error ProposalNotSchedulable();
    error ProposalLifetimePassed();
    error ProposeLock();
    error ProposalOngoing(
        uint256 id,
        uint256 currentTimestamp,
        uint256 proposalEndTimestamp
    );
    error ProposalNotPassed();
    error QuorumNotReached(uint256 id, uint256 votesTotal, uint256 quorum);
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
        uint256 votesTotal;
        bool executable;
        bool quadraticVoting;
    }

    struct GovernanceParameters {
        uint256 proposalLifetime;
        uint256 quorum;
        uint256 voteLockTime;
        uint256 proposeLockTime;
        uint256 voteChangeTime;
        uint256 voteChangeCutOff;
        uint256 opThreshold;
        uint256 maxVotingStreak;
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

    ///*** KEY ADDRESSES ***///
    address public sciManagerAddress;
    address public admin;
    address private signer;

    ///*** STORAGE & MAPPINGS ***///
    uint256 private _index;
    GovernanceParameters public governanceParams;
    mapping(uint256 => Proposal) private proposals;
    mapping(address => uint256) private votingStreak;
    mapping(address => mapping(uint256 => UserVoteData)) private userVoteData;

    ///*** ROLES ***///
    bytes32 public constant GUARD_ROLE = keccak256("GUARD_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    ///*** ENUMERATORS ***///

    /**
     * @notice Enumerates the different states a proposal can be in.
     */
    enum ProposalStatus {
        Active,
        Scheduled,
        Executed,
        Completed, //Completed status only for proposals that cannot be executed
        Canceled
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
    event AdminUpdated(address indexed user, address indexed newAddress);
    event GovExecUpdated(address indexed user, address indexed newAddress);
    event GovGuardUpdated(address indexed user, address indexed newAddress);
    event ParameterUpdated(bytes32 indexed param, uint256 data);
    event Proposed(
        uint256 indexed id,
        address indexed user,
        string info,
        uint256 startBlockNum,
        uint256 endTimestamp,
        address action,
        bool executable,
        bool quadraticVoting
    );
    event PoUpdated(address indexed user, address po);
    event SignerUpdated(address indexed newAddress);
    event SciManagerUpdated(address indexed user, address indexed newAddress);
    event StatusUpdated(
        uint256 indexed id,
        ProposalStatus indexed status
    );

    event Voted(
        uint256 indexed id,
        address indexed user,
        bool indexed support,
        uint256 amount
    );

    event VotesUpdated(
        uint256 indexed id,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 votesTotal
    );

    constructor(
        address sciManager_,
        address admin_,
        address po_,
        address signer_
    ) {
        if (
            sciManager_ == address(0) ||
            admin_ == address(0) ||
            po_ == address(0) ||
            signer_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }
        sciManagerAddress = sciManager_;
        admin = admin_;
        po = IPo(po_);
        signer = signer_;

        governanceParams.opThreshold = 5000e18;
        governanceParams.quorum = 567300e18; // 3% of circulating supply of 18.91 million SCI
        governanceParams.maxVotingStreak = 5;
        governanceParams.proposalLifetime = 30 minutes;
        governanceParams.voteLockTime = 0; //normally 1 week
        governanceParams.proposeLockTime = 0; //normally 1 week
        governanceParams.voteChangeTime = 10 minutes; //normally 1 hour
        governanceParams.voteChangeCutOff = 10 minutes; //normally 3 days

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
        emit AdminUpdated(oldAdmin, newAdmin);
    }

    /**
     * @dev sets the sciManager address
     */
    function setsciManagerAddress(
        address newsciManagerAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        sciManagerAddress = newsciManagerAddress;
        emit SciManagerUpdated(msg.sender, newsciManagerAddress);
    }

    /**
     * @dev sets the GovernorExecution address
     */
    function setGovExec(
        address newGovExecAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govExec = IGovernorExecution(newGovExecAddress);
        emit GovExecUpdated(msg.sender, newGovExecAddress);
    }

    /**
     * @dev sets the GovernorGuard address
     */
    function setGovGuard(
        address newGovGuardAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govGuard = IGovernorGuard(newGovGuardAddress);
        _grantRole(GUARD_ROLE, newGovGuardAddress);
        emit GovGuardUpdated(msg.sender, newGovGuardAddress);
    }

    /**
     * @dev sets the signer address
     */
    function setSigner(
        address newSigner
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = newSigner;
        emit SignerUpdated(newSigner);
    }

    /**
     * @dev sets the PO token address and interface
     */
    function setPoToken(address po_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        po = IPo(po_);
        emit PoUpdated(msg.sender, po_);
    }

    /**
     * @dev sets the governance parameters given data
     * @param param the parameter of interest
     * @param data the data assigned to the parameter
     */
    function setGovernanceParameter(
        bytes32 param,
        uint256 data
    ) external onlyExecutor {
        if (param == "proposalLifetime")
            governanceParams.proposalLifetime = data;
        else if (param == "quorum") governanceParams.quorum = data;
        else if (param == "voteLockTime") governanceParams.voteLockTime = data;
        else if (param == "proposeLockTime")
            governanceParams.proposeLockTime = data;
        else if (param == "voteChangeTime")
            governanceParams.voteChangeTime = data;
        else if (param == "voteChangeCutOff")
            governanceParams.voteChangeCutOff = data;
        else if (param == "opThreshold") governanceParams.opThreshold = data;
        else if (param == "maxVotingStreak" && data <= 5 && data >= 1)
            governanceParams.maxVotingStreak = data;
        else revert InvalidGovernanceParameter();

        emit ParameterUpdated(param, data);
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

        ISciManager sciManager = ISciManager(sciManagerAddress);

        _validateLockingRequirements(sciManager, msg.sender);

        uint256 currentIndex = _storeProposal(
            info,
            action,
            quadraticVoting,
            executable,
            sciManager
        );

        emit Proposed(
            currentIndex,
            msg.sender,
            proposals[currentIndex].info,
            proposals[currentIndex].startBlockNum,
            proposals[currentIndex].endTimestamp,
            proposals[currentIndex].action,
            proposals[currentIndex].executable,
            proposals[currentIndex].quadraticVoting
        );

        emit StatusUpdated(
            currentIndex,
            proposals[currentIndex].status
        );

        emit VotesUpdated(
            currentIndex,
            proposals[currentIndex].votesFor,
            proposals[currentIndex].votesAgainst,
            proposals[currentIndex].votesTotal
        );

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

        uint256 votingRights = ISciManager(sciManagerAddress)
            .getLatestUserRights(msg.sender);

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

        uint256 votingRights = ISciManager(sciManagerAddress)
            .getLatestUserRights(msg.sender);

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

            emit StatusUpdated(
                id,
                proposals[id].status
            );
        } else {
            revert ProposalNotSchedulable();
        }
    }

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

        _grantRole(EXECUTOR_ROLE, proposals[id].action);

        govExec.execution(proposals[id].action);

        _revokeRole(EXECUTOR_ROLE, proposals[id].action);

        proposals[id].status = ProposalStatus.Executed;

        emit StatusUpdated(
            id,
            proposals[id].status
        );
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

        emit StatusUpdated(
            id,
            proposals[id].status
        );
    }

    /**
     * @dev cancels the proposal
     * @param id the _index of the proposal of interest
     */
    function cancel(uint256 id) external nonReentrant onlyRole(GUARD_ROLE) {
        if (
            proposals[id].status == ProposalStatus.Executed ||
            proposals[id].status == ProposalStatus.Canceled
        ) revert IncorrectPhase(proposals[id].status);

        if (proposals[id].executable) govExec.cancel(proposals[id].action);

        proposals[id].status = ProposalStatus.Canceled;

        emit StatusUpdated(
            id,
            proposals[id].status
        );
    }

    /**
     * @dev cancels the proposal
     * @param id the _index of the proposal of interest
     */
    function cancelRejected(uint256 id) external nonReentrant {
        if (id >= _index) revert ProposalInexistent();
        if (
            proposals[id].status == ProposalStatus.Canceled
        ) revert IncorrectPhase(proposals[id].status);

        bool schedulable = _proposalSchedulingChecks(id, false);

        if (!schedulable) {
            proposals[id].status = ProposalStatus.Canceled;

            emit StatusUpdated(
                id,
                proposals[id].status
            );
        } else {
            revert ProposalNotCancelable();
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
     */
    function getGovernanceParameters()
        public
        view
        returns (GovernanceParameters memory)
    {
        return governanceParams;
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
    function getProposal(
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
                proposals[id].votesTotal,
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
        uint256 sqrtQuorum = Math.sqrt(governanceParams.quorum / 10 ** 18) *
            10 ** 18;

        bool isProposalOngoing = block.timestamp < proposals[id].endTimestamp;

        bool isProposalActive = proposals[id].status == ProposalStatus.Active;

        bool quorumReached = proposals[id].quadraticVoting
            ? proposals[id].votesTotal >= sqrtQuorum
            : proposals[id].votesTotal >= governanceParams.quorum;

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
                    proposals[id].votesTotal,
                    proposals[id].quadraticVoting
                        ? sqrtQuorum
                        : governanceParams.quorum
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
            revert ProposalLifetimePassed();
        if (
            userVoteData[voter][id].voted &&
            block.timestamp >=
            proposals[id].endTimestamp - governanceParams.voteChangeCutOff
        ) revert VoteChangeNotAllowedAfterCutOff();
        if (
            userVoteData[voter][id].voted &&
            block.timestamp >
            userVoteData[voter][id].initialVoteTimestamp +
                governanceParams.voteChangeTime
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
            proposals[id].votesTotal -= voteData.previousVoteAmount;
        }

        if (support) {
            proposals[id].votesFor += actualVotes;
        } else {
            proposals[id].votesAgainst += actualVotes;
        }
        proposals[id].votesTotal += actualVotes;

        if (!voteData.voted) {
            if (id > 0 && userVoteData[msg.sender][id - 1].voted) {
                votingStreak[msg.sender] = votingStreak[msg.sender] >=
                    governanceParams.maxVotingStreak
                    ? governanceParams.maxVotingStreak
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

        ISciManager(sciManagerAddress).voted(
            msg.sender,
            block.timestamp + governanceParams.voteLockTime
        );

        emit Voted(id, msg.sender, support, actualVotes);

        emit VotesUpdated(
            id,
            proposals[id].votesFor,
            proposals[id].votesAgainst,
            proposals[id].votesTotal
        );
    }

    /**
     * @dev Checks if the proposer satisfies the sciManager requirements for proposal submission.
     * @param sciManager The sciManager contract interface to check locked amounts.
     * @param proposer Address of the user making the proposal.
     *
     * @notice Reverts with InsufficientBalance if the locked amount is below the required threshold.
     * Reverts with ProposeLock if the proposer's tokens are locked due to a recent proposal.
     */
    function _validateLockingRequirements(
        ISciManager sciManager,
        address proposer
    ) internal view {
        if (sciManager.getLockedSci(proposer) < governanceParams.opThreshold)
            revert InsufficientBalance(
                sciManager.getLockedSci(proposer),
                governanceParams.opThreshold
            );

        if (sciManager.getProposeLockEnd(proposer) > block.timestamp)
            revert ProposeLock();
    }

    /**
     * @dev Stores a new operation proposal in the contract's state and updates sciManager.
     * @param action contract address executing an action.
     * @param quadraticVoting Boolean indicating if quadratic voting is enabled for this proposal.
     * @param sciManager The sciManager contract interface used for updating the proposer's status.
     * @return uint256 The _index where the new proposal is stored.
     *
     * @notice The function increments the operations proposal _index after storing.
     * It also updates the sciManager contract to reflect the new proposal.
     */
    function _storeProposal(
        string memory info,
        address action,
        bool quadraticVoting,
        bool executable,
        ISciManager sciManager
    ) internal returns (uint256) {
        Proposal memory proposal = Proposal(
            info,
            block.number,
            block.timestamp + governanceParams.proposalLifetime,
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

        sciManager.proposed(
            msg.sender,
            block.timestamp + governanceParams.proposeLockTime
        );

        return currentIndex;
    }
}
