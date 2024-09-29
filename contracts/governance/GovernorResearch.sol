// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "./../interfaces/IStaking.sol";
import "./../interfaces/IGovernorExecution.sol";
import "./../interfaces/IGovernorGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../contracts/governance/GovernorExecutorRoleManager.sol";

contract GovernorResearch is GovernorExecutorRoleManager, ReentrancyGuard {
    ///*** ERRORS ***///

    error CannotComplete();
    error CannotExecute();
    error ContractTerminated(uint256 blockNumber);
    error IncorrectPhase(ProposalStatus);
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error InvalidInput();
    error ProposalLifeTimePassed();
    error ProposalNotPassed();
    error ProposalOngoing(uint256 id, uint256 currentBlock, uint256 endBlock);
    error ProposalInexistent();
    error QuorumNotReached(uint256 id, uint256 totalVotes, uint256 quorum);
    error Unauthorized(address caller);
    error VoteChangeNotAllowedAfterCutOff();
    error VoteChangeWindowExpired();

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
    }

    struct UserVoteData {
        bool voted; // Whether the user has voted
        uint256 initialVoteTimestamp; // The timestamp of when the user first voted
        bool previousSupport; // Whether the user supported the last vote
    }

    ///*** INTERFACES ***///
    IGovernorExecution private govExec;
    IGovernorGuard private govGuard;

    ///*** GOVERNANCE PARAMETERS ***///
    uint256 public proposalLifeTime;
    uint256 public quorum;
    uint256 public proposeLockTime;
    uint256 public voteLockTime;
    uint256 public voteChangeTime;
    uint256 public voteChangeCutOff;

    ///*** KEY ADDRESSES ***///
    address public stakingAddress;
    address public admin;
    address public researchFundingWallet;
    address public usdc;
    address public sci;

    ///*** STORAGE & MAPPINGS ***///
    uint256 public ddThreshold;
    uint256 private _index;
    bool public terminated = false;
    uint256 constant VOTE = 1;
    mapping(uint256 => Proposal) private proposals;
    mapping(address => uint8) private proposedResearch;
    mapping(address => mapping(uint256 => UserVoteData)) private userVoteData;

    ///*** ROLES ***///
    bytes32 public constant GUARD_ROLE = keccak256("GUARD_ROLE");
    bytes32 public constant STAKING_ROLE = keccak256("STAKING_ROLE");
    bytes32 public constant DUE_DILIGENCE_ROLE =
        keccak256("DUE_DILIGENCE_ROLE");

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

    ///*** MODIFIERS ***///

    /**
     * @notice Ensures operations can only proceed if the contract has not been terminated.
     */
    modifier notTerminated() {
        if (terminated) revert ContractTerminated(block.number);
        _;
    }

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
    event Executed(
        uint256 indexed id,
        address indexed govExec,
        address indexed action
    );
    event Proposed(
        uint256 indexed id,
        address indexed user,
        address indexed action
    );
    event Voted(
        uint256 indexed id,
        address indexed user,
        bool indexed support,
        uint256 amount
    );
    event Scheduled(uint256 indexed id);

    event SetGovParam(bytes32 indexed param, uint256 data);

    event SetNewAdmin(address indexed user, address indexed newAddress);

    event SetNewGovExecAddress(
        address indexed user,
        address indexed newAddress
    );

    event SetNewGovGuardAddress(
        address indexed user,
        address indexed newAddress
    );

    event SetNewResearchFundingWallet(
        address indexed user,
        address indexed SetNewResearchFundingWallet
    );

    event SetNewStakingAddress(
        address indexed user,
        address indexed newAddress
    );
    event Terminated(address admin, uint256 blockNumber);

    constructor(
        address stakingAddress_,
        address admin_,
        address researchFundingWallet_,
        address usdc_,
        address sci_
    ) {
        if (
            stakingAddress_ == address(0) ||
            admin_ == address(0) ||
            researchFundingWallet_ == address(0) ||
            usdc_ == address(0) ||
            sci_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }
        stakingAddress = stakingAddress_;
        admin = admin_;
        researchFundingWallet = researchFundingWallet_;
        usdc = usdc_;
        sci = sci_;

        ddThreshold = 1000e18;

        proposalLifeTime = 4 weeks;
        quorum = 1;
        voteLockTime = 1 weeks;
        proposeLockTime = 1 weeks;
        voteChangeTime = 1 hours;
        voteChangeCutOff = 3 days;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        _grantRole(DUE_DILIGENCE_ROLE, admin_);
        _grantRole(DUE_DILIGENCE_ROLE, researchFundingWallet_);

        _setRoleAdmin(DUE_DILIGENCE_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(STAKING_ROLE, stakingAddress_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the GovernorExecution address
     */
    function setGovExec(
        address newGovExecAddress
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        govExec = IGovernorExecution(newGovExecAddress);
        emit SetNewGovExecAddress(msg.sender, newGovExecAddress);
    }

    /**
     * @dev sets the GovernorGuard address
     */
    function setGovGuard(
        address newGovGuardAddress
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        govGuard = IGovernorGuard(newGovGuardAddress);
        _grantRole(GUARD_ROLE, newGovGuardAddress);
        emit SetNewGovGuardAddress(msg.sender, newGovGuardAddress);
    }

    /**
     * @dev terminates the governance smart contract
     */
    function setTerminated() external notTerminated onlyRole(STAKING_ROLE) {
        terminated = true;
        emit Terminated(msg.sender, block.number);
    }

    /**
     * @dev grants Due Diligence role to members
     * @param members the addresses of the DAO members
     */
    function grantDueDiligenceRole(
        address[] memory members
    ) external notTerminated onlyExecutor {
        IStaking staking = IStaking(stakingAddress);
        for (uint256 i = 0; i < members.length; i++) {
            _validateStakingRequirements(staking, members[i]);
            _grantRole(DUE_DILIGENCE_ROLE, members[i]);
        }
    }

    /**
     * @dev revokes Due Diligence role to member
     * @param members the address of the DAO member
     */
    function revokeDueDiligenceRole(
        address[] memory members
    ) external notTerminated onlyExecutor {
        for (uint256 i = 0; i < members.length; i++) {
            _revokeRole(DUE_DILIGENCE_ROLE, members[i]);
        }
    }

    /**
     * @dev checks if user has the DD role
     * @param member the address of the DAO member
     */
    function checkDueDiligenceRole(
        address member
    ) external view returns (bool) {
        return hasRole(DUE_DILIGENCE_ROLE, member);
    }

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
     * @dev sets the donation wallet address
     */
    function setResearchFundingWallet(
        address newresearchFundingWallet
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        researchFundingWallet = newresearchFundingWallet;
        emit SetNewResearchFundingWallet(msg.sender, newresearchFundingWallet);
    }

    /**
     * @dev sets the staking address
     */
    function setStakingAddress(
        address newStakingAddress
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingAddress = newStakingAddress;
        emit SetNewStakingAddress(msg.sender, newStakingAddress);
    }

    /**
     * @dev sets the governance parameters given data
     * @param param the parameter of interest
     * @param data the data assigned to the parameter
     */
    function setGovParams(
        bytes32 param,
        uint256 data
    ) external notTerminated onlyExecutor {
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

        //the number of tokens the user must have staked to propose and vote
        if (param == "ddThreshold") ddThreshold = data;

        emit SetGovParam(param, data);
    }

    /**
     * @dev proposes a research project in need of funding
     *      at least one option needs to be proposed
     * @param info ipfs hash of project proposal
     * @param action the address of the smart contract executing the proposal
     */
    function propose(
        string memory info,
        address action
    )
        external
        nonReentrant
        notTerminated
        onlyRole(DUE_DILIGENCE_ROLE)
        returns (uint256)
    {
        if (bytes(info).length == 0) revert InvalidInput();

        bool executable;

        if (action == address(0)) {
            executable = false;
        } else {
            executable = true;
        }

        IStaking staking = IStaking(stakingAddress);
        _validateStakingRequirements(staking, msg.sender);

        uint256 currentIndex = _storeProposal(info, action, executable);

        emit Proposed(currentIndex, msg.sender, action);

        return currentIndex;
    }

    /**
     * @dev vote for an of option of a given proposal
     *      using the rights from the most recent snapshot
     * @param id the index of the proposal
     * @param support true if in support of proposal
     */
    function vote(
        uint256 id,
        bool support
    ) external notTerminated nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        _votingChecks(id, msg.sender);

        IStaking staking = IStaking(stakingAddress);

        _validateStakingRequirements(staking, msg.sender);

        _recordVote(id, support);
    }

    /**
     * @dev finalizes the voting phase for a research proposal
     * @param id the index of the proposal of interest
     */
    function schedule(
        uint256 id
    ) external nonReentrant notTerminated onlyRole(DUE_DILIGENCE_ROLE) {
        if (id >= _index) revert ProposalInexistent();

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
     * @dev executes the proposal using USDC
     * @param id the index of the proposal of interest
     */
    function execute(
        uint256 id
    ) external payable notTerminated nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        // Check if proposal exists and has finalized voting
        if (id >= _index) revert ProposalInexistent();
        if (proposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(proposals[id].status);

        if (!proposals[id].executable) revert CannotExecute();

        govExec.execution(proposals[id].action);

        proposals[id].status = ProposalStatus.Executed;

        emit Executed(id, address(govExec), proposals[id].action);
    }

    /**
     * @dev completes a non-executable proposal
     * @param id the _index of the proposal of interest
     */
    function complete(
        uint256 id
    ) external nonReentrant notTerminated onlyRole(DUE_DILIGENCE_ROLE) {
        if (id > _index) revert ProposalInexistent();

        if (proposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(proposals[id].status);

        if (proposals[id].executable) {
            revert CannotComplete();
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
     * @param id the index of the proposal of interest
     */
    function cancelRejected(
        uint256 id
    ) external nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        if (id >= _index) revert ProposalInexistent();

        bool schedulable = _proposalSchedulingChecks(id, false);

        if (!schedulable) {
            proposals[id].status = ProposalStatus.Cancelled;

            emit Cancelled(id, true);
        }
    }

    /**
     * @dev returns the proposal index
     */
    function getProposalIndex() external view returns (uint256) {
        return _index;
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
            ddThreshold
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
                proposals[id].executable
            );
    }

    /**
     * @notice Retrieves voting data for a specific user on a specific proposal.
     * @dev This function returns the user's voting data for a proposal identified by its unique ID. It ensures the proposal exists before fetching the data.
     *      If the proposal ID is invalid (greater than the current maximum index), it reverts with `ProposalInexistent`.
     * @param user The address of the user whose voting data is being requested.
     * @param id The unique identifier (index) of the proposal for which the user's voting data is being requested. This ID is sequentially assigned to proposals as they are created.
     * @return voted A boolean indicating whether the user has voted on this proposal. `true` means the user has cast a vote, `false` means they have not.
     * @return initialVoteTimestamp The timestamp of when the user last voted on this proposal. The value represents seconds since Unix epoch (block timestamp).
     * @return previousSupport A boolean indicating whether the user supported the proposal in their last vote. `true` means they supported it, `false` means they opposed it.
     */
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
                userVoteData[user][id].previousSupport
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
        bool isProposalOngoing = block.timestamp < proposals[id].endTimestamp;

        bool isProposalActive = proposals[id].status == ProposalStatus.Active;

        bool quorumReached = proposals[id].totalVotes >= quorum;

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
                revert QuorumNotReached(id, proposals[id].totalVotes, quorum);
            }
            if (!isVotesForGreaterThanVotesAgainst) {
                revert ProposalNotPassed();
            }
        }

        return passed;
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
     */
    function _recordVote(uint id, bool support) internal {
        UserVoteData storage voteData = userVoteData[msg.sender][id];

        // Deduct previous votes if the user has already voted
        if (voteData.voted) {
            if (voteData.previousSupport) {
                proposals[id].votesFor -= VOTE;
            } else {
                proposals[id].votesAgainst -= VOTE;
            }
            proposals[id].totalVotes -= VOTE;
        }

        if (support) {
            proposals[id].votesFor += VOTE;
        } else {
            proposals[id].votesAgainst += VOTE;
        }
        proposals[id].totalVotes += VOTE;

        voteData.voted = true;
        voteData.previousSupport = support;

        if (voteData.initialVoteTimestamp == 0) {
            voteData.initialVoteTimestamp = block.timestamp;
        }

        IStaking(stakingAddress).voted(
            msg.sender,
            block.timestamp + voteLockTime
        );

        emit Voted(id, msg.sender, support, VOTE);
    }

    /**
     * @dev Validates if the proposer meets the staking requirements for proposing research.
     * @param staking The staking contract interface used to check the staked SCI.
     * @param member The address of the member initiating an action.
     *
     * @notice This function reverts with InsufficientBalance if the staked SCI is below the threshold.
     * The staked SCI amount and required threshold are provided in the revert message.
     */
    function _validateStakingRequirements(
        IStaking staking,
        address member
    ) internal view {
        uint256 stakedSci = staking.getStakedSci(member);
        if (stakedSci < ddThreshold) {
            revert InsufficientBalance(stakedSci, ddThreshold);
        }
    }

    /**
     * @dev Stores a new research proposal in the contract's state.
     * @param info ipfs file link
     * @param action the contract address executing the proposal
     * @return uint256 The index of the newly stored research proposal.
     *
     * @notice The function increments the _index after storing the proposal.
     * The proposal is stored with an Active status and initialized voting counters.
     * The function returns the index at which the new proposal is stored.
     */
    function _storeProposal(
        string memory info,
        address action,
        bool executable
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
            executable
        );

        uint256 currentIndex = _index++;
        proposals[currentIndex] = proposal;

        return currentIndex;
    }
}
