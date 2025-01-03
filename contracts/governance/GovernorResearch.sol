// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "./../interfaces/ISciManager.sol";
import "./../interfaces/IGovernorExecution.sol";
import "./../interfaces/IGovernorGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title GovernorResearch
 * @dev Implements DAO governance functionalities strictly for Due Diligence Crew members including proposing, voting, and on-chain executing of proposals specifically for the funding of research.
 * It integrates with external contracts for sciManager validation, participation and proposal execution.
 */
contract GovernorResearch is AccessControl, ReentrancyGuard {
    
    ///*** ERRORS ***///
    error CannotBeZeroAddress();
    error CannotComplete();
    error CannotExecute();
    error IncorrectPhase(ProposalStatus);
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error InvalidInput();
    error InvalidGovernanceParameter();
    error ProposalLifetimePassed();
    error ProposalNotPassed();
    error ProposalOngoing(uint256 index, uint256 currentBlock, uint256 endBlock);
    error ProposalInexistent();
    error QuorumNotReached(uint256 index, uint256 votesTotal, uint256 quorum);
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
        uint256 votesTotal;
        bool executable;
    }

    struct GovernanceParameters {
        uint256 proposalLifetime;
        uint256 quorum;
        uint256 voteLockTime;
        uint256 proposeLockTime;
        uint256 voteChangeTime;
        uint256 voteChangeCutOff;
        uint256 ddThreshold;
    }

    struct UserVoteData {
        bool voted; // Whether the user has voted
        uint256 initialVoteTimestamp; // The timestamp of when the user first voted
        bool previousSupport; // Whether the user supported the last vote
    }

    ///*** INTERFACES ***///
    IGovernorExecution private _govExec;
    IGovernorGuard private _govGuard;

    ///*** KEY ADDRESSES ***///
    address public sciManagerAddress;
    address public admin;
    address public researchFundingWallet;

    ///*** STORAGE & MAPPINGS ***///
    uint256 private _proposalIndex;
    uint256 constant _VOTE = 1;
    GovernanceParameters public governanceParams;
    mapping(uint256 => Proposal) private _proposals;
    mapping(address => uint8) private _proposedResearch;
    mapping(address => mapping(uint256 => UserVoteData)) private _userVoteData;

    ///*** ROLES ***///
    bytes32 public constant GUARD_ROLE = keccak256("GUARD_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
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
        Canceled
    }

    ///*** MODIFIERS ***///

    /**
     * @dev Modifier to check if the caller has the `EXECUTOR_ROLE` in `GovernorExecutor`.
     */
    modifier onlyExecutor() {
        if (!_govExec.hasRole(EXECUTOR_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /*** EVENTS ***/
    event AdminUpdated(address indexed user, address indexed newAddress);
    event GovExecUpdated(address indexed user, address indexed newAddress);
    event Elected(address indexed elected);
    event Impeached(address indexed impeached);
    event GovGuardUpdated(address indexed user, address indexed newAddress);
    event ParameterUpdated(bytes32 indexed param, uint256 data);
    event Proposed(
        uint256 indexed index,
        address indexed user,
        string info,
        uint256 startBlockNum,
        uint256 endTimestamp,
        address action,
        bool executable
    );
    event SciManagerUpdated(address indexed user, address indexed newAddress);
    event StatusUpdated(
        uint256 indexed index,
        ProposalStatus indexed status
    );
    event ResearchFundingWalletUpdated(
        address indexed user,
        address indexed setNewResearchFundingWallet
    );
    event Voted(
        uint256 indexed index,
        address indexed user,
        bool indexed support,
        uint256 amount
    );
    event VotesUpdated(
        uint256 indexed index,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 votesTotal
    );

    constructor(
        address sciManager_,
        address admin_,
        address researchFundingWallet_
    ) {
        if (
            sciManager_ == address(0) ||
            admin_ == address(0) ||
            researchFundingWallet_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }
        sciManagerAddress = sciManager_;
        admin = admin_;
        researchFundingWallet = researchFundingWallet_;

        governanceParams.ddThreshold = 1000e18;
        governanceParams.proposalLifetime = 30 minutes;
        governanceParams.quorum = 1;
        governanceParams.voteLockTime = 0 weeks;
        governanceParams.proposeLockTime = 0 weeks;
        governanceParams.voteChangeTime = 10 minutes; //normally 1 hour
        governanceParams.voteChangeCutOff = 10 minutes; //normally 3 days

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        _grantRole(DUE_DILIGENCE_ROLE, admin_);
        _grantRole(DUE_DILIGENCE_ROLE, researchFundingWallet_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the GovernorExecution address
     */
    function setGovExec(
        address newGovExecAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _govExec = IGovernorExecution(newGovExecAddress);
        emit GovExecUpdated(msg.sender, newGovExecAddress);
    }

    /**
     * @dev sets the GovernorGuard address
     */
    function setGovGuard(
        address newGovGuardAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _govGuard = IGovernorGuard(newGovGuardAddress);
        _grantRole(GUARD_ROLE, newGovGuardAddress);
        emit GovGuardUpdated(msg.sender, newGovGuardAddress);
    }

    /**
     * @dev grants Due Diligence role to members
     * @param members the addresses of the DAO members
     */
    function grantDueDiligenceRole(
        address[] memory members
    ) external onlyExecutor {
        ISciManager sciManager = ISciManager(sciManagerAddress);
        for (uint256 i = 0; i < members.length; i++) {
            _validateLockingRequirements(sciManager, members[i]);
            _grantRole(DUE_DILIGENCE_ROLE, members[i]);
            emit Elected(members[i]);
        }
    }

    /**
     * @dev grants Due Diligence role to members
     * @param members the addresses of the DAO members
     */
    function grantDueDiligenceRoleByAdmin(
        address[] memory members
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ISciManager sciManager = ISciManager(sciManagerAddress);
        for (uint256 i = 0; i < members.length; i++) {
            _validateLockingRequirements(sciManager, members[i]);
            _grantRole(DUE_DILIGENCE_ROLE, members[i]);
            emit Elected(members[i]);
        }
    }

    /**
     * @dev revokes Due Diligence role to member
     * @param members the address of the DAO member
     */
    function revokeDueDiligenceRole(
        address[] memory members
    ) external onlyExecutor {
        for (uint256 i = 0; i < members.length; i++) {
            _revokeRole(DUE_DILIGENCE_ROLE, members[i]);
            emit Impeached(members[i]);
        }
    }

    /**
     * @dev revokes Due Diligence role to member
     * @param members the address of the DAO member
     */
    function revokeDueDiligenceRoleByAdmin(
        address[] memory members
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < members.length; i++) {
            _revokeRole(DUE_DILIGENCE_ROLE, members[i]);
            emit Impeached(members[i]);
        }
    }

    /**
     * @dev checks if user has the DD role
     * @param member the address of the DAO member
     */
    function checkDueDiligenceRole(
        address member
    ) public view returns (bool) {
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
        emit AdminUpdated(oldAdmin, newAdmin);
    }

    /**
     * @dev sets the research funding wallet address
     */
    function setResearchFundingWallet(
        address newresearchFundingWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        researchFundingWallet = newresearchFundingWallet;
        emit ResearchFundingWalletUpdated(msg.sender, newresearchFundingWallet);
    }

    /**
     * @dev sets the sciManager address
     */
    function setSciManagerAddress(
        address newSciManagerAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        sciManagerAddress = newSciManagerAddress;
        emit SciManagerUpdated(msg.sender, newSciManagerAddress);
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
        else if (param == "ddThreshold") governanceParams.ddThreshold = data;
        else revert InvalidGovernanceParameter();

        emit ParameterUpdated(param, data);
    }

    /**
     * @dev sets the governance parameters given data
     * @param param the parameter of interest
     * @param data the data assigned to the parameter
     */
    function setGovernanceParameterByAdmin(
        bytes32 param,
        uint256 data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
        else if (param == "ddThreshold") governanceParams.ddThreshold = data;
        else revert InvalidGovernanceParameter();

        emit ParameterUpdated(param, data);
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
    ) external nonReentrant onlyRole(DUE_DILIGENCE_ROLE) returns (uint256) {
        if (bytes(info).length == 0) revert InvalidInput();

        bool executable;

        if (action == address(0)) {
            executable = false;
        } else {
            executable = true;
        }

        ISciManager sciManager = ISciManager(sciManagerAddress);
        _validateLockingRequirements(sciManager, msg.sender);

        uint256 currentIndex = _storeProposal(info, action, executable);

        emit Proposed(
            currentIndex,
            msg.sender,
            _proposals[currentIndex].info,
            _proposals[currentIndex].startBlockNum,
            _proposals[currentIndex].endTimestamp,
            _proposals[currentIndex].action,
            _proposals[currentIndex].executable
        );

        emit StatusUpdated(
            currentIndex,
            _proposals[currentIndex].status
        );

        emit VotesUpdated(
            currentIndex,
            _proposals[currentIndex].votesFor,
            _proposals[currentIndex].votesAgainst,
            _proposals[currentIndex].votesTotal
        );

        return currentIndex;
    }

    /**
     * @dev vote for an of option of a given proposal
     *      using the rights from the most recent snapshot
     * @param index the index of the proposal
     * @param support true if in support of proposal
     */
    function vote(
        uint256 index,
        bool support
    ) external nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        _votingChecks(index, msg.sender);

        ISciManager sciManager = ISciManager(sciManagerAddress);

        _validateLockingRequirements(sciManager, msg.sender);

        _recordVote(index, support);
    }

    /**
     * @dev finalizes the voting phase for a research proposal
     * @param index the index of the proposal of interest
     */
    function schedule(
        uint256 index
    ) external nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        if (index >= _proposalIndex) revert ProposalInexistent();

        bool schedulable = _proposalSchedulingChecks(index, true);

        if (schedulable) {
            if (_proposals[index].executable) {
                _govExec.schedule(_proposals[index].action);
            }
            _proposals[index].status = ProposalStatus.Scheduled;

            emit StatusUpdated(
                index,
                _proposals[index].status
            );
        }
    }

    /**
     * @dev executes the proposal
     * @param index the index of the proposal of interest
     */
    function execute(
        uint256 index
    ) external payable nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        // Check if proposal exists and has finalized voting
        if (index >= _proposalIndex) revert ProposalInexistent();
        if (_proposals[index].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(_proposals[index].status);

        if (!_proposals[index].executable) revert CannotExecute();

        _govExec.execution(_proposals[index].action);

        _proposals[index].status = ProposalStatus.Executed;

        emit StatusUpdated(
            index,
            _proposals[index].status
        );
    }

    /**
     * @dev completes a non-executable proposal
     * @param index the _proposalIndex of the proposal of interest
     */
    function complete(
        uint256 index
    ) external nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        if (index > _proposalIndex) revert ProposalInexistent();

        if (_proposals[index].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(_proposals[index].status);

        if (_proposals[index].executable) {
            revert CannotComplete();
        }

        _proposals[index].status = ProposalStatus.Completed;

        emit StatusUpdated(
            index,
            _proposals[index].status
        );
    }

    /**
     * @dev cancels the proposal
     * @param index the _proposalIndex of the proposal of interest
     */
    function cancel(uint256 index) external nonReentrant onlyRole(GUARD_ROLE) {
        if (
            _proposals[index].status == ProposalStatus.Executed ||
            _proposals[index].status == ProposalStatus.Canceled
        ) revert IncorrectPhase(_proposals[index].status);
        
        if (_proposals[index].executable) _govExec.cancel(_proposals[index].action);

        _proposals[index].status = ProposalStatus.Canceled;

        emit StatusUpdated(
            index,
            _proposals[index].status
        );
    }

    /**
     * @dev cancels the proposal
     * @param index the index of the proposal of interest
     */
    function cancelRejected(
        uint256 index
    ) external nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        if (index >= _proposalIndex) revert ProposalInexistent();
        if (
            _proposals[index].status == ProposalStatus.Canceled
        ) revert IncorrectPhase(_proposals[index].status);
        
        bool schedulable = _proposalSchedulingChecks(index, false);

        if (!schedulable) {
            _proposals[index].status = ProposalStatus.Canceled;

            emit StatusUpdated(
                index,
                _proposals[index].status
            );
        }
    }

    /**
     * @dev returns the proposal index
     */
    function getProposalIndex() external view returns (uint256) {
        return _proposalIndex;
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
     * @notice Retrieves detailed information about a specific governance proposal.
     * @dev This function returns comprehensive details of a proposal identified by its unique ID. It ensures the proposal exists before fetching the details. If the proposal ID is invalid (greater than the current maximum index), it reverts with `ProposalInexistent`.
     * @param index The unique identifier (index) of the proposal whose information is being requested. This ID is sequentially assigned to proposals as they are created.
     */
    function getProposal(
        uint256 index
    ) external view returns (Proposal memory) {
        if (index > _proposalIndex) revert ProposalInexistent();

        // Return a struct with the proposal details
        return
            Proposal(
                _proposals[index].info,
                _proposals[index].startBlockNum,
                _proposals[index].endTimestamp,
                _proposals[index].status,
                _proposals[index].action,
                _proposals[index].votesFor,
                _proposals[index].votesAgainst,
                _proposals[index].votesTotal,
                _proposals[index].executable
            );
    }

    /**
     * @notice Retrieves voting data for a specific user on a specific proposal.
     * @dev This function returns the user's voting data for a proposal identified by its unique ID. It ensures the proposal exists before fetching the data.
     *      If the proposal ID is invalid (greater than the current maximum index), it reverts with `ProposalInexistent`.
     * @param user The address of the user whose voting data is being requested.
     * @param index The unique identifier (index) of the proposal for which the user's voting data is being requested. This ID is sequentially assigned to proposals as they are created.
     * @return voted A boolean indicating whether the user has voted on this proposal. `true` means the user has cast a vote, `false` means they have not.
     * @return initialVoteTimestamp The timestamp of when the user last voted on this proposal. The value represents seconds since Unix epoch (block timestamp).
     * @return previousSupport A boolean indicating whether the user supported the proposal in their last vote. `true` means they supported it, `false` means they opposed it.
     */
    /**
     * @notice Retrieves voting data for a specific user on a specific proposal.
     * @dev This function returns the user's voting data for a proposal identified by its unique ID. It ensures the proposal exists before fetching the data.
     *      If the proposal ID is invalid (greater than the current maximum index), it reverts with `ProposalInexistent`.
     * @param user The address of the user whose voting data is being requested.
     * @param index The unique identifier (index) of the proposal for which the user's voting data is being requested. This ID is sequentially assigned to proposals as they are created.
     */
    function getUserVoteData(
        address user,
        uint256 index
    ) external view returns (UserVoteData memory) {
        if (index > _proposalIndex) revert ProposalInexistent();
        return
            UserVoteData(
                _userVoteData[user][index].voted,
                _userVoteData[user][index].initialVoteTimestamp,
                _userVoteData[user][index].previousSupport
            );
    }

    ///*** INTERNAL FUNCTIONS ***///

    /**
     * @dev Internal function that performs checks to determine if a proposal can be scheduled.
     *      - Checks include proposal status, quorum requirements, and vote tally.
     *      - Optionally reverts with specific errors if `revertable` is set to true.
     * @param index The unique identifier of the proposal.
     * @param revertable If true, reverts with an error if any check fails.
     * @return passed A boolean value indicating whether all the checks are passed.
     */
    function _proposalSchedulingChecks(
        uint256 index,
        bool revertable
    ) internal view returns (bool) {
        bool isProposalOngoing = block.timestamp < _proposals[index].endTimestamp;

        bool isProposalActive = _proposals[index].status == ProposalStatus.Active;

        bool quorumReached = _proposals[index].votesTotal >=
            governanceParams.quorum;

        bool isVotesForGreaterThanVotesAgainst = _proposals[index].votesFor >
            _proposals[index].votesAgainst;

        bool passed = !isProposalOngoing &&
            isProposalActive &&
            quorumReached &&
            isVotesForGreaterThanVotesAgainst;

        if (!passed && revertable) {
            if (isProposalOngoing) {
                revert ProposalOngoing(
                    index,
                    block.timestamp,
                    _proposals[index].endTimestamp
                );
            }
            if (!isProposalActive) {
                revert IncorrectPhase(_proposals[index].status);
            }
            if (!quorumReached) {
                revert QuorumNotReached(
                    index,
                    _proposals[index].votesTotal,
                    governanceParams.quorum
                );
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
     * @param index The index of the proposal on which to vote.
     * @param voter the user that wants to vote on the given proposal index
     *
     *
     */
    function _votingChecks(uint index, address voter) internal view {
        if (index >= _proposalIndex) revert ProposalInexistent();
        if (_proposals[index].status != ProposalStatus.Active)
            revert IncorrectPhase(_proposals[index].status);
        if (block.timestamp > _proposals[index].endTimestamp)
            revert ProposalLifetimePassed();
        if (
            _userVoteData[voter][index].voted &&
            block.timestamp >=
            _proposals[index].endTimestamp - governanceParams.voteChangeCutOff
        ) revert VoteChangeNotAllowedAfterCutOff();
        if (
            _userVoteData[voter][index].voted &&
            block.timestamp >
            _userVoteData[voter][index].initialVoteTimestamp +
                governanceParams.voteChangeTime
        ) {
            revert VoteChangeWindowExpired();
        }
    }

    /**
     * @dev Records a vote on a proposal, updating the vote totals and voter status.
     *      This function is called after all preconditions checked by `_votingChecks` are met.
     *
     * @param index The index of the proposal on which to vote.
     * @param support A boolean indicating whether the vote is in support of (true) or against (false) the proposal.
     */
    function _recordVote(uint index, bool support) internal {
        UserVoteData storage voteData = _userVoteData[msg.sender][index];

        if (voteData.voted) {
            if (voteData.previousSupport) {
                _proposals[index].votesFor -= _VOTE;
            } else {
                _proposals[index].votesAgainst -= _VOTE;
            }
            _proposals[index].votesTotal -= _VOTE;
        }

        if (support) {
            _proposals[index].votesFor += _VOTE;
        } else {
            _proposals[index].votesAgainst += _VOTE;
        }
        _proposals[index].votesTotal += _VOTE;

        voteData.voted = true;
        voteData.previousSupport = support;

        if (voteData.initialVoteTimestamp == 0) {
            voteData.initialVoteTimestamp = block.timestamp;
        }

        ISciManager(sciManagerAddress).voted(
            msg.sender,
            block.timestamp + governanceParams.voteLockTime
        );

        emit Voted(index, msg.sender, support, _VOTE);

        emit VotesUpdated(
            index,
            _proposals[index].votesFor,
            _proposals[index].votesAgainst,
            _proposals[index].votesTotal
        );
    }

    /**
     * @dev Validates if the proposer meets the sciManager requirements for proposing research.
     * @param sciManager The contract interface used to check the number of locked SCI.
     * @param member The address of the member initiating an action.
     */
    function _validateLockingRequirements(
        ISciManager sciManager,
        address member
    ) internal view {
        uint256 lockedSci = sciManager.getLockedSci(member);
        if (lockedSci < governanceParams.ddThreshold) {
            revert InsufficientBalance(lockedSci, governanceParams.ddThreshold);
        }
    }

    /**
     * @dev Stores a new research proposal in the contract's state.
     * @param info ipfs file link
     * @param action the contract address executing the proposal
     * @return uint256 The index of the newly stored research proposal.
     */
    function _storeProposal(
        string memory info,
        address action,
        bool executable
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
            executable
        );

        uint256 currentIndex = _proposalIndex++;
        _proposals[currentIndex] = proposal;

        return currentIndex;
    }
}
