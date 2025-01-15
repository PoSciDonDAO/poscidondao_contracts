// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../interfaces/IActionCloneFactory.sol";
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
 * @dev Implements DAO governance functionalities including proposing, voting, and on-chain executing of proposals.
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
    error FactoryNotSet();
    error ProposalInexistent();
    error IncorrectPhase(ProposalStatus);
    error InvalidActionContract(address action);
    error InvalidActionType(uint256 actionType);
    error InvalidInput();
    error InvalidGovernanceParameter();
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error NoTokensToClaim();
    error ProposalNotCancelable();
    error ProposalNotSchedulable();
    error ProposalLifetimePassed();
    error ProposeLock();
    error ProposalOngoing(
        uint256 index,
        uint256 currentTimestamp,
        uint256 proposalEndTimestamp
    );
    error ProposalNotPassed();
    error ProposalTooNew();
    error QuorumNotReached(uint256 index, uint256 votesTotal, uint256 quorum);
    error Unauthorized(address caller);
    error VoteChangeNotAllowedAfterCutOff();
    error VoteChangeWindowExpired();
    error VoteLockShorterThanProposal(
        uint256 voteLockTime,
        uint256 proposalLifetime
    );
    error VotingRightsThresholdNotReached();

    ///*** STRUCTS ***///
    struct Proposal {
        string info;
        uint256 startTimestamp;
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
        uint256 votingRightsThreshold;
        uint256 votingDelay;
    }

    struct UserVoteData {
        bool voted; // Whether the user has voted
        uint256 initialVoteTimestamp; // The timestamp of when the user first voted
        bool previousSupport; // Whether the user supported the last vote
        uint256 previousVoteAmount; // The amount of votes cast in the last vote
        bool poClaimed; //Whether the user has claimed PO tokens for the vote on the proposal
        uint256 votingStreakAtVote; // Streak value when the user voted
    }

    ///*** INTERFACES ***///
    IPo private _po;
    IGovernorExecution private _govExec;
    IGovernorGuard private _govGuard;

    ///*** KEY ADDRESSES ***///
    address public sciManagerAddress;
    address public admin;
    address private _signer;

    ///*** STORAGE & MAPPINGS ***///
    uint256 private _proposalIndex;
    GovernanceParameters public governanceParams;
    IActionCloneFactory public factory;
    mapping(uint256 => Proposal) private _proposals;
    mapping(address => uint256) private _votingStreak;
    mapping(address => uint256) private _lastClaimedProposal;
    mapping(address => uint256) private _latestVoteTimestamp;
    mapping(address => mapping(uint256 => UserVoteData)) private _userVoteData;

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
        if (!_govExec.hasRole(EXECUTOR_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /*** EVENTS ***/
    event AdminSet(address indexed user, address indexed newAddress);
    event Claimed(address indexed user, uint256 amount);
    event FactoryUpdated(address indexed user, address newAddress);
    event GovExecUpdated(address indexed user, address indexed newAddress);
    event GovGuardUpdated(address indexed user, address indexed newAddress);
    event ParameterUpdated(bytes32 indexed param, uint256 data);
    event Proposed(
        uint256 indexed index,
        address indexed user,
        string info,
        uint256 startTimestamp,
        uint256 endTimestamp,
        address action,
        bool executable,
        bool quadraticVoting
    );
    event PoUpdated(address indexed user, address _po);
    event SignerUpdated(address indexed newAddress);
    event SciManagerUpdated(address indexed user, address indexed newAddress);
    event StatusUpdated(uint256 indexed index, ProposalStatus indexed status);

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
        address po_,
        address signer_,
        address factory_
    ) {
        if (
            sciManager_ == address(0) ||
            admin_ == address(0) ||
            po_ == address(0) ||
            signer_ == address(0) ||
            factory_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }
        sciManagerAddress = sciManager_;
        admin = admin_;
        _po = IPo(po_);
        _signer = signer_;
        factory = IActionCloneFactory(factory_);

        governanceParams.opThreshold = 5000e18;
        governanceParams.quorum = 567300e18; // 3% of maximum supply of 18.91 million SCI
        governanceParams.maxVotingStreak = 5;
        governanceParams.proposalLifetime = 30 minutes;
        governanceParams.voteLockTime = 10 minutes; //normally 2 weeks
        governanceParams.proposeLockTime = 0; //normally 2 weeks
        governanceParams.voteChangeTime = 12 hours; //normally 1 hour
        governanceParams.voteChangeCutOff = 3 days; //normally 2 days
        governanceParams.votingRightsThreshold = 1e18; //at least 1 vote to prevent spamming
        governanceParams.votingDelay = 5 minutes; //5 minutes to prevent flash loan attacks

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev Updates the admin address and transfers admin role.
     * @param newAdmin The address to be set as the new admin.
     */
    function setAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert CannotBeZeroAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        emit AdminSet(oldAdmin, newAdmin);
    }

    /**
     * @dev Sets the sciManager address
     * @param newSciManagerAddress The address to be set as the sci manager contract
     */
    function setSciManagerAddress(
        address newSciManagerAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newSciManagerAddress == address(0)) revert CannotBeZeroAddress();
        sciManagerAddress = newSciManagerAddress;
        emit SciManagerUpdated(msg.sender, newSciManagerAddress);
    }

    /**
     * @dev Sets the sciManager address
     * @param newFactoryAddress The address to be set as the sci manager contract
     */
    function setFactoryAddress(
        address newFactoryAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFactoryAddress == address(0)) revert CannotBeZeroAddress();
        factory = IActionCloneFactory(newFactoryAddress);
        emit FactoryUpdated(msg.sender, newFactoryAddress);
    }

    /**
     * @dev Sets the GovernorExecution address
     * @param newGovExecAddress The address to be set as the governor executor
     */
    function setGovExec(
        address newGovExecAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovExecAddress == address(0)) revert CannotBeZeroAddress();
        _govExec = IGovernorExecution(newGovExecAddress);
        emit GovExecUpdated(msg.sender, newGovExecAddress);
    }

    /**
     * @dev Sets the GovernorGuard address
     * @param newGovGuardAddress The address to be set as the governor guard

     */
    function setGovGuard(
        address newGovGuardAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovGuardAddress == address(0)) revert CannotBeZeroAddress();
        _govGuard = IGovernorGuard(newGovGuardAddress);
        _grantRole(GUARD_ROLE, newGovGuardAddress);
        emit GovGuardUpdated(msg.sender, newGovGuardAddress);
    }

    /**
     * @dev Sets the _signer address
     * @param newSigner The address to be set as the _signer used to sign off-chain messages
     */
    function setSigner(
        address newSigner
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _signer = newSigner;
        emit SignerUpdated(newSigner);
    }

    /**
     * @dev Sets the PO token address and interface
     * @param po_ the address of the PO token
     */
    function setPoToken(address po_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _po = IPo(po_);
        emit PoUpdated(msg.sender, po_);
    }

    /**
     * @dev Sets the governance parameters given data
     * @param param the parameter of interest
     * @param data the data assigned to the parameter
     */
    function setGovernanceParameter(
        bytes32 param,
        uint256 data
    ) external onlyExecutor {
        if (param == "proposalLifetime") {
            if (data > governanceParams.voteLockTime)
                revert VoteLockShorterThanProposal(
                    governanceParams.voteLockTime,
                    data
                );
            governanceParams.proposalLifetime = data;
        } else if (param == "voteLockTime") {
            if (data < governanceParams.proposalLifetime)
                revert VoteLockShorterThanProposal(
                    data,
                    governanceParams.proposalLifetime
                );
            governanceParams.voteLockTime = data;
        } else if (param == "quorum") governanceParams.quorum = data;
        else if (param == "proposeLockTime")
            governanceParams.proposeLockTime = data;
        else if (param == "voteChangeTime")
            governanceParams.voteChangeTime = data;
        else if (param == "voteChangeCutOff")
            governanceParams.voteChangeCutOff = data;
        else if (param == "opThreshold") governanceParams.opThreshold = data;
        else if (param == "maxVotingStreak" && data <= 10 && data >= 1)
            governanceParams.maxVotingStreak = data;
        else if (param == "votingRightsThreshold")
            governanceParams.votingRightsThreshold = data;
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
        if (param == "proposalLifetime") {
            if (data > governanceParams.voteLockTime)
                revert VoteLockShorterThanProposal(
                    governanceParams.voteLockTime,
                    data
                );
            governanceParams.proposalLifetime = data;
        } else if (param == "voteLockTime") {
            if (data < governanceParams.proposalLifetime)
                revert VoteLockShorterThanProposal(
                    data,
                    governanceParams.proposalLifetime
                );
            governanceParams.voteLockTime = data;
        } else if (param == "quorum") governanceParams.quorum = data;
        else if (param == "proposeLockTime")
            governanceParams.proposeLockTime = data;
        else if (param == "voteChangeTime")
            governanceParams.voteChangeTime = data;
        else if (param == "voteChangeCutOff")
            governanceParams.voteChangeCutOff = data;
        else if (param == "opThreshold") governanceParams.opThreshold = data;
        else if (param == "maxVotingStreak" && data <= 10 && data >= 1)
            governanceParams.maxVotingStreak = data;
        else if (param == "votingRightsThreshold")
            governanceParams.votingRightsThreshold = data;
        else if (param == "votingDelay")
            governanceParams.votingDelay = data; //only by admin
        else revert InvalidGovernanceParameter();

        emit ParameterUpdated(param, data);
    }

    /**
     * @dev Proposes a change in DAO operations.
     * @param info IPFS hash containing proposal details
     * @param actionType Type of action to create:
     *        0 = No action / Not Executable
     *        1 = Transaction
     *        2 = Election
     *        3 = Impeachment
     *        4 = ParameterChange
     * @param actionParams Encoded parameters specific to the action type:
     *        Election: (address[] targetWallets, address governorResearch, address governorExecutor)
     *        Impeachment: (address[] targetWallets, address governorResearch, address governorExecutor)
     *        ParameterChange: (address gov, address governorExecutor, string param, uint256 data)
     *        Transaction: (address fundingWallet, address targetWallet, uint256 amountUsdc, uint256 amountSci, address governorExecutor)
     * @param quadraticVoting Whether quadratic voting is enabled for the proposal
     * @return uint256 Index of the newly created proposal
     */
    function propose(
        string memory info,
        uint256 actionType,
        bytes memory actionParams,
        bool quadraticVoting
    ) external nonReentrant returns (uint256) {
        if (bytes(info).length == 0) revert InvalidInput();
        if (actionType > 4) revert InvalidActionType(actionType);
        if (address(factory) == address(0)) revert FactoryNotSet();
        if (governanceParams.voteLockTime < governanceParams.proposalLifetime) {
            revert VoteLockShorterThanProposal(
                governanceParams.voteLockTime,
                governanceParams.proposalLifetime
            );
        }

        address action;
        bool executable = actionType != 0;

        if (executable) {
            action = factory.createAction(actionType, actionParams);

            uint256 codeSize;
            assembly {
                codeSize := extcodesize(action)
            }
            if (codeSize == 0) {
                revert InvalidActionContract(action);
            }
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
            _proposals[currentIndex].info,
            _proposals[currentIndex].startTimestamp,
            _proposals[currentIndex].endTimestamp,
            _proposals[currentIndex].action,
            _proposals[currentIndex].executable,
            _proposals[currentIndex].quadraticVoting
        );

        emit StatusUpdated(currentIndex, _proposals[currentIndex].status);

        emit VotesUpdated(
            currentIndex,
            _proposals[currentIndex].votesFor,
            _proposals[currentIndex].votesAgainst,
            _proposals[currentIndex].votesTotal
        );

        return currentIndex;
    }

    /**
     * @dev Vote for an option of a given proposal
     *      using the rights from the most recent snapshot
     * @param index the _proposalIndex of the proposal
     * @param support user's choice to support a proposal or not
     */
    function voteStandard(uint index, bool support) external nonReentrant {
        _votingChecks(index, msg.sender);

        if (_proposals[index].quadraticVoting) revert CannotVoteOnQVProposals();

        uint256 votingRights = ISciManager(sciManagerAddress)
            .getLatestUserRights(msg.sender);

        if (votingRights >= governanceParams.votingRightsThreshold) {
            _recordVote(index, support, votingRights);
        } else {
            revert VotingRightsThresholdNotReached();
        }
    }

    /**
     * @dev Vote for an option of a given proposal
     *      using the rights from the most recent snapshot
     * @param index the _proposalIndex of the proposal
     * @param support user's choice to support a proposal or not
     * @param isUnique The status of the uniqueness of the account casting the vote.
     * @param signature The signature of the data related to the account's uniqueness.
     */
    function voteQV(
        uint index,
        bool support,
        bool isUnique,
        bytes memory signature
    ) external nonReentrant {
        _votingChecks(index, msg.sender);
        _uniquenessCheck(index, msg.sender, isUnique, signature);

        uint256 votingRights = ISciManager(sciManagerAddress)
            .getLatestUserRights(msg.sender);

        if (votingRights >= governanceParams.votingRightsThreshold) {
            uint256 actualVotes = Math.sqrt(votingRights / 10 ** 18) * 10 ** 18;
            _recordVote(index, support, actualVotes);
        } else {
            revert VotingRightsThresholdNotReached();
        }
    }

    /**
     * @dev Schedules the the execution or completion of a proposal
     * @param index the _proposalIndex of the proposal of interest
     */
    function schedule(uint256 index) external nonReentrant {
        if (index >= _proposalIndex) revert ProposalInexistent();

        if (block.timestamp < _proposals[index].endTimestamp)
            revert ProposalOngoing(
                index,
                block.timestamp,
                _proposals[index].endTimestamp
            );

        bool schedulable = _proposalSchedulingChecks(index, true);

        if (schedulable) {
            if (_proposals[index].executable) {
                _govExec.schedule(_proposals[index].action);
            }
            _proposals[index].status = ProposalStatus.Scheduled;

            emit StatusUpdated(index, _proposals[index].status);
        } else {
            revert ProposalNotSchedulable();
        }
    }

    /**
     * @dev Executes a scheduled proposal
     * @param index The ID of the proposal to be executed.
     */
    function execute(uint256 index) external nonReentrant {
        if (index >= _proposalIndex) revert ProposalInexistent();

        if (_proposals[index].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(_proposals[index].status);

        if (!_proposals[index].executable) revert CannotExecute();

        _grantRole(EXECUTOR_ROLE, _proposals[index].action);

        _govExec.execution(_proposals[index].action);

        _revokeRole(EXECUTOR_ROLE, _proposals[index].action);

        _proposals[index].status = ProposalStatus.Executed;

        emit StatusUpdated(index, _proposals[index].status);
    }

    /**
     * @dev Completes off-chain execution proposals
     * @param index the _proposalIndex of the proposal of interest
     */
    function complete(uint256 index) external nonReentrant {
        if (index > _proposalIndex) revert ProposalInexistent();

        if (_proposals[index].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(_proposals[index].status);

        if (_proposals[index].executable) {
            revert ExecutableProposalsCannotBeCompleted();
        }

        _proposals[index].status = ProposalStatus.Completed;

        emit StatusUpdated(index, _proposals[index].status);
    }

    /**
     * @dev Cancels the proposal by governor guard
     * @param index the _proposalIndex of the proposal of interest
     */
    function cancel(uint256 index) external nonReentrant onlyRole(GUARD_ROLE) {
        if (
            _proposals[index].status == ProposalStatus.Executed ||
            _proposals[index].status == ProposalStatus.Canceled
        ) revert IncorrectPhase(_proposals[index].status);

        if (_proposals[index].executable)
            _govExec.cancel(_proposals[index].action);

        _proposals[index].status = ProposalStatus.Canceled;

        emit StatusUpdated(index, _proposals[index].status);
    }

    /**
     * @dev cancels the proposal if rejected
     * @param index the _proposalIndex of the proposal of interest
     */
    function cancelRejected(uint256 index) external nonReentrant {
        if (index >= _proposalIndex) revert ProposalInexistent();
        if (_proposals[index].status == ProposalStatus.Canceled)
            revert IncorrectPhase(_proposals[index].status);

        if (block.timestamp < _proposals[index].endTimestamp)
            revert ProposalOngoing(
                index,
                block.timestamp,
                _proposals[index].endTimestamp
            );

        bool schedulable = _proposalSchedulingChecks(index, false);

        if (!schedulable) {
            _proposals[index].status = ProposalStatus.Canceled;

            emit StatusUpdated(index, _proposals[index].status);
        } else {
            revert ProposalNotCancelable();
        }
    }

    /**
     * @dev Allows a user to claim their accumulated unclaimed PO tokens earned through voting.
     */
    function claimPo() external {
        uint256 totalPoToClaim = 0;
        uint256 startIndex = _lastClaimedProposal[msg.sender];
        uint256 endIndex = _proposalIndex;

        for (uint256 i = startIndex; i < endIndex; i++) {
            UserVoteData storage voteData = _userVoteData[msg.sender][i];

            if (!voteData.voted || voteData.poClaimed) {
                continue;
            }

            uint256 sqrtQuorum = Math.sqrt(governanceParams.quorum / 10 ** 18) *
                10 ** 18;
            bool quorumReached = _proposals[i].quadraticVoting
                ? _proposals[i].votesTotal >= sqrtQuorum
                : _proposals[i].votesTotal >= governanceParams.quorum;

            if (quorumReached) {
                totalPoToClaim += voteData.votingStreakAtVote;
                voteData.poClaimed = true;

                _lastClaimedProposal[msg.sender] = i + 1;
            }
        }

        if (totalPoToClaim == 0) {
            revert NoTokensToClaim();
        }

        _po.mint(msg.sender, totalPoToClaim);

        emit Claimed(msg.sender, totalPoToClaim);
    }

    /**
     * @dev Returns the PO token address
     */
    function getPoToken() external view returns (address) {
        return address(_po);
    }

    /**
     * @dev Returns the operations proposal _proposalIndex
     */
    function getProposalIndex() external view returns (uint256) {
        return _proposalIndex;
    }

    /**
     * @dev Returns the number of unclaimed tokens from the user
     */
    function getLastClaimedProposal(
        address user
    ) external view returns (uint256) {
        return _lastClaimedProposal[user];
    }

    /**
     * @dev Returns the latest vote timestamp from the user
     */
    function getLatestVoteTimestamp(
        address user
    ) external view returns (uint256) {
        return _latestVoteTimestamp[user];
    }

    /**
     * @dev Returns the _signer address
     */
    function getSigner()
        external
        view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (address)
    {
        return _signer;
    }

    /**
     * @dev Retrieves the current governance parameters.
     */
    function getGovernanceParameters()
        external
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
                _userVoteData[user][index].previousSupport,
                _userVoteData[user][index].previousVoteAmount,
                _userVoteData[user][index].poClaimed,
                _userVoteData[user][index].votingStreakAtVote
            );
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

        return
            Proposal(
                _proposals[index].info,
                _proposals[index].startTimestamp,
                _proposals[index].endTimestamp,
                _proposals[index].status,
                _proposals[index].action,
                _proposals[index].votesFor,
                _proposals[index].votesAgainst,
                _proposals[index].votesTotal,
                _proposals[index].executable,
                _proposals[index].quadraticVoting
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
        uint256 sqrtQuorum = Math.sqrt(governanceParams.quorum / 10 ** 18) *
            10 ** 18;

        bool isProposalOngoing = block.timestamp <
            _proposals[index].endTimestamp;

        bool isProposalActive = _proposals[index].status ==
            ProposalStatus.Active;

        bool quorumReached = _proposals[index].quadraticVoting
            ? _proposals[index].votesTotal >= sqrtQuorum
            : _proposals[index].votesTotal >= governanceParams.quorum;

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
                    _proposals[index].quadraticVoting
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
     * @param index The index of the proposal on which to vote.
     * @param isUnique The status of the uniqueness of the account casting the vote.
     * @param signature The signature of the data related to the account's uniqueness.
     */
    function _uniquenessCheck(
        uint256 index,
        address user,
        bool isUnique,
        bytes memory signature
    ) internal view {
        if (_proposals[index].quadraticVoting) {
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
                _signer,
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
     * @param index The index of the proposal on which to vote.
     * @param voter the user that wants to vote on the given proposal index
     *
     *
     */
    function _votingChecks(uint256 index, address voter) internal view {
        if (index >= _proposalIndex) revert ProposalInexistent();
        if (
            block.timestamp <
            _proposals[index].startTimestamp + governanceParams.votingDelay
        ) revert ProposalTooNew();
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
     * @param actualVotes The effective number of votes to record, which may be adjusted for voting type, such as quadratic.
     */
    function _recordVote(
        uint256 index,
        bool support,
        uint256 actualVotes
    ) internal {
        UserVoteData storage voteData = _userVoteData[msg.sender][index];

        if (voteData.voted) {
            if (voteData.previousSupport) {
                _proposals[index].votesFor -= voteData.previousVoteAmount;
            } else {
                _proposals[index].votesAgainst -= voteData.previousVoteAmount;
            }
            _proposals[index].votesTotal -= voteData.previousVoteAmount;
        }

        if (support) {
            _proposals[index].votesFor += actualVotes;
        } else {
            _proposals[index].votesAgainst += actualVotes;
        }
        _proposals[index].votesTotal += actualVotes;

        if (!voteData.voted) {
            if (index > 0 && _userVoteData[msg.sender][index - 1].voted) {
                _votingStreak[msg.sender] = _votingStreak[msg.sender] >=
                    governanceParams.maxVotingStreak
                    ? governanceParams.maxVotingStreak
                    : _votingStreak[msg.sender] + 1;
            } else {
                _votingStreak[msg.sender] = 1;
            }

            voteData.votingStreakAtVote = _votingStreak[msg.sender];
        }

        voteData.voted = true;
        voteData.previousSupport = support;
        voteData.previousVoteAmount = actualVotes;

        if (voteData.initialVoteTimestamp == 0) {
            voteData.initialVoteTimestamp = block.timestamp;
        }

        _latestVoteTimestamp[msg.sender] = block.timestamp;

        ISciManager(sciManagerAddress).voted(
            msg.sender,
            block.timestamp + governanceParams.voteLockTime
        );

        emit Voted(index, msg.sender, support, actualVotes);

        emit VotesUpdated(
            index,
            _proposals[index].votesFor,
            _proposals[index].votesAgainst,
            _proposals[index].votesTotal
        );
    }

    /**
     * @dev Checks if the proposer satisfies the sciManager requirements for proposal submission.
     * @param sciManager The sciManager contract interface to check locked amounts.
     * @param proposer Address of the user making the proposal.
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
            block.timestamp,
            block.timestamp + governanceParams.proposalLifetime,
            ProposalStatus.Active,
            action,
            0,
            0,
            0,
            executable,
            quadraticVoting
        );

        uint256 currentIndex = _proposalIndex++;
        _proposals[currentIndex] = proposal;

        sciManager.proposed(
            msg.sender,
            block.timestamp + governanceParams.proposeLockTime
        );

        return currentIndex;
    }
}
