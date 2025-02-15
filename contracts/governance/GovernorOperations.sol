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
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error InvalidActionContract(address action);
    error InvalidActionType(uint256 actionType, uint256 limit);
    error InvalidInput();
    error InvalidGovernanceParameter();
    error InvalidSignatureProvided();
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
    error SameAddress();
    error Unauthorized(address caller);
    error VoteChangeNotAllowedAfterCutOff();
    error VoteChangeWindowExpired();
    error VoteLockShorterThanProposal(
        uint256 voteLockTime,
        uint256 proposalLifetime
    );
    error VotingRightsThresholdNotReached();
    error UserNotUnique();
    error NotQuadraticVotingProposal();
    error InvalidParameterValue(bytes32 param, uint256 value, string reason);
    error NotAContract(address contractAddress);

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
    IActionCloneFactory private _factory;

    ///*** KEY ADDRESSES ***///
    address public sciManagerContract;
    address public admin;
    address private _signer;

    ///*** STORAGE & MAPPINGS ***///
    uint256 private _proposalIndex;
    uint256 private _actionTypeLimit;
    GovernanceParameters public governanceParams;
    mapping(uint256 => Proposal) private _proposals;
    mapping(address => uint256) private _votingStreak;
    mapping(address => uint256) private _latestVoteTimestamp;
    mapping(address => mapping(uint256 => UserVoteData)) private _userVoteData;
    mapping(address => uint256) private _userNonces;
    uint256 public constant SIGNATURE_VALIDITY_PERIOD = 1 hours;

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
    event ActionTypeLimitUpdated(address indexed user, uint256 newLimit);
    event AdminSet(address indexed user, address indexed newAddress);
    event Claimed(address indexed user, uint256 amount);
    event FactorySet(address indexed user, address newAddress);
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

    event VotingStreakUpdated(
        address indexed user,
        uint256 oldStreak,
        uint256 newStreak
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
        sciManagerContract = sciManager_;
        admin = admin_;
        _po = IPo(po_);
        _signer = signer_;
        _actionTypeLimit = 4;

        governanceParams.opThreshold = 5000e18;
        governanceParams.quorum = 367300e18; // 3% of maximum supply of 18.91 million SCI
        governanceParams.maxVotingStreak = 5; //can be adjusted based on community feedback
        governanceParams.proposalLifetime = 7 days; //prod: 2 weeks, test: 30 minutes
        governanceParams.voteLockTime = 8 days; //prod: 2 weeks, test: 31 minutes (as long as voteLockTime > proposalLifetime)
        governanceParams.proposeLockTime = 14 days; //prod: 2 weeks, test: 0 minutes
        governanceParams.voteChangeTime = 1 days; //prod: 1-24 hours, test: 10 minutes
        governanceParams.voteChangeCutOff = 2 days; //prod: 3 days, test: 10 minutes
        governanceParams.votingRightsThreshold = 1e18; //at least 1 vote to prevent spamming
        governanceParams.votingDelay = 5 minutes; //to prevent flash loan attacks

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev Updates the admin address and transfers admin role.
     * @param newAdmin The address to be set as the new admin.
     */
    function setAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert CannotBeZeroAddress();
        if (newAdmin == msg.sender) revert SameAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        emit AdminSet(oldAdmin, newAdmin);
    }

    /**
     * @dev Sets the new factory contract address
     * @param newActionTypeLimit The new maximum action type ID allowed
     * @notice Cannot be set lower than 4 to preserve core action types
     *         Core action types: 0 = No action / Not Executable, 1 = Transaction, 2 = Election, 3 = Impeachment, 4 = ParameterChange
     *         These can be disabled through the factory contract if needed
     */
    function setActionTypeLimit(
        uint256 newActionTypeLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newActionTypeLimit < 4)
            revert InvalidActionType(newActionTypeLimit, 4);
        _actionTypeLimit = newActionTypeLimit;
        emit ActionTypeLimitUpdated(msg.sender, newActionTypeLimit);
    }

    /**
     * @dev Sets the sciManager address
     * @param newSciManager The address to be set as the sci manager contract
     */
    function setSciManager(
        address newSciManager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newSciManager == address(0)) revert CannotBeZeroAddress();
        if (newSciManager == sciManagerContract) revert SameAddress();
        uint256 size;
        assembly {
            size := extcodesize(newSciManager)
        }
        if (size == 0) revert NotAContract(newSciManager);
        sciManagerContract = newSciManager;
        emit SciManagerUpdated(msg.sender, newSciManager);
    }

    /**
     * @dev Sets the new factory contract address for operations proposals
     * @param newFactory The address to be set as the factory contract
     */
    function setFactory(
        address newFactory
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFactory == address(0)) revert CannotBeZeroAddress();
        if (newFactory == address(_factory)) revert SameAddress();

        uint256 size;
        assembly {
            size := extcodesize(newFactory)
        }
        if (size == 0) revert NotAContract(newFactory);

        _factory = IActionCloneFactory(newFactory);
        emit FactorySet(msg.sender, newFactory);
    }

    /**
     * @dev Sets the GovernorExecution address
     * @param newGovExec The address to be set as the governor executor
     */
    function setGovExec(
        address newGovExec
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovExec == address(0)) revert CannotBeZeroAddress();
        if (newGovExec == address(_govExec)) revert SameAddress();
        uint256 size;
        assembly {
            size := extcodesize(newGovExec)
        }
        if (size == 0) revert NotAContract(newGovExec);

        _govExec = IGovernorExecution(newGovExec);
        emit GovExecUpdated(msg.sender, newGovExec);
    }

    /**
     * @dev Sets the GovernorGuard address
     * @param newGovGuard The address to be set as the governor guard
     */
    function setGovGuard(
        address newGovGuard
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovGuard == address(0)) revert CannotBeZeroAddress();
        if (newGovGuard == address(_govGuard)) revert SameAddress();

        uint256 size;
        assembly {
            size := extcodesize(newGovGuard)
        }
        if (size == 0) revert NotAContract(newGovGuard);

        _govGuard = IGovernorGuard(newGovGuard);
        _grantRole(GUARD_ROLE, newGovGuard);
        emit GovGuardUpdated(msg.sender, newGovGuard);
    }

    /**
     * @dev Sets the _signer address used to sign off-chain messages. Signer's private key is DAO-controlled.
     * @param newSigner The address to be set as the _signer used to sign off-chain messages
     */
    function setSigner(
        address newSigner
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newSigner == address(0)) revert CannotBeZeroAddress();
        _signer = newSigner;
        emit SignerUpdated(newSigner);
    }

    /**
     * @dev Sets the PO token address and interface
     * @param po_ the address of the PO token
     */
    function setPoToken(address po_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (po_ == address(0)) revert CannotBeZeroAddress();
        if (po_ == address(_po)) revert SameAddress();

        uint256 size;
        assembly {
            size := extcodesize(po_)
        }
        if (size == 0) revert NotAContract(po_);
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
            // Ensure proposal lifetime is reasonable (between 1 day and 30 days)
            if (data < 1 days || data > 30 days) {
                revert InvalidParameterValue(
                    param,
                    data,
                    "Must be between 1 and 30 days"
                );
            }
            if (data > governanceParams.voteLockTime)
                revert VoteLockShorterThanProposal(
                    governanceParams.voteLockTime,
                    data
                );
            governanceParams.proposalLifetime = data;
        } else if (param == "voteLockTime") {
            // Vote lock time must be at least 1 day and not more than 60 days
            if (data < 1 days || data > 60 days) {
                revert InvalidParameterValue(
                    param,
                    data,
                    "Must be between 1 and 60 days"
                );
            }
            if (data < governanceParams.proposalLifetime)
                revert VoteLockShorterThanProposal(
                    data,
                    governanceParams.proposalLifetime
                );
            governanceParams.voteLockTime = data;
        } else if (param == "quorum") {
            // Quorum must be at least 0.1% of total supply
            if (data < 18910e18) {
                // 0.1% of 18.91M total supply
                revert InvalidParameterValue(
                    param,
                    data,
                    "Must be at least 0.1% of total supply"
                );
            }
            governanceParams.quorum = data;
        } else if (param == "proposeLockTime") {
            // Propose lock time must be at least 1 day and not more than 30 days
            if (data < 1 days || data > 30 days) {
                revert InvalidParameterValue(
                    param,
                    data,
                    "Must be between 1 and 30 days"
                );
            }
            governanceParams.proposeLockTime = data;
        } else if (param == "voteChangeTime") {
            // Vote change window must be at least 1 hour and not more than proposal lifetime
            if (data < 1 hours || data > governanceParams.proposalLifetime) {
                revert InvalidParameterValue(
                    param,
                    data,
                    "Must be between 1 hour and proposal lifetime"
                );
            }
            governanceParams.voteChangeTime = data;
        } else if (param == "voteChangeCutOff") {
            // Vote change cutoff must be at least 1 hour and not more than proposal lifetime
            if (data < 1 hours || data > governanceParams.proposalLifetime) {
                revert InvalidParameterValue(
                    param,
                    data,
                    "Must be between 1 hour and proposal lifetime"
                );
            }
            governanceParams.voteChangeCutOff = data;
        } else if (param == "opThreshold") {
            // Operations threshold must be at least 10 SCI
            if (data < 10e18) {
                revert InvalidParameterValue(
                    param,
                    data,
                    "Must be at least 10 SCI"
                );
            }
            governanceParams.opThreshold = data;
        } else if (param == "maxVotingStreak") {
            // Max voting streak must be at least 1
            if (data < 1) {
                revert InvalidParameterValue(param, data, "Must be at least 1");
            }
            governanceParams.maxVotingStreak = data;
        } else if (param == "votingRightsThreshold") {
            // Voting rights threshold must be at least 1 SCI
            if (data < 1e18) {
                revert InvalidParameterValue(
                    param,
                    data,
                    "Must be at least 1 SCI"
                );
            }
            governanceParams.votingRightsThreshold = data;
        } else if (param == "votingDelay") {
            // Voting delay must be at least 1 minute
            if (data < 1 minutes) {
                revert InvalidParameterValue(
                    param,
                    data,
                    "Must be at least 1 minute"
                );
            }
            governanceParams.votingDelay = data;
        } else revert InvalidGovernanceParameter();

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
        if (actionType > _actionTypeLimit)
            revert InvalidActionType(actionType, _actionTypeLimit);
        if (address(_factory) == address(0)) revert FactoryNotSet();
        if (governanceParams.voteLockTime < governanceParams.proposalLifetime) {
            revert VoteLockShorterThanProposal(
                governanceParams.voteLockTime,
                governanceParams.proposalLifetime
            );
        }

        address action;
        bool executable = actionType != 0;

        if (executable) {
            action = _factory.createAction(actionType, actionParams);

            uint256 codeSize;
            assembly {
                codeSize := extcodesize(action)
            }
            if (codeSize == 0) {
                revert InvalidActionContract(action);
            }
        }

        ISciManager sciManager = ISciManager(sciManagerContract);

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

        uint256 votingRights = ISciManager(sciManagerContract)
            .getLatestUserRights(msg.sender);

        if (votingRights >= governanceParams.votingRightsThreshold) {
            _recordVote(index, support, votingRights);
        } else {
            revert VotingRightsThresholdNotReached();
        }
    }

    /**
     * @dev Vote for an option of a given proposal using quadratic voting
     * @param index The index of the proposal
     * @param support User's choice to support a proposal or not
     * @param isUnique The status of the uniqueness of the account casting the vote
     * @param timestamp The timestamp when the signature was created
     * @param signature The signature of the data related to the account's uniqueness. Is signed off-chain by the DAO-controlled signer.
     */
    function voteQV(
        uint256 index,
        bool support,
        bool isUnique,
        uint256 timestamp,
        bytes memory signature
    ) external nonReentrant {
        _votingChecks(index, msg.sender);

        if (!_proposals[index].quadraticVoting) {
            revert NotQuadraticVotingProposal();
        }

        bool verified = _verify(
            msg.sender,
            isUnique,
            timestamp,
            index,
            signature
        );
        if (!verified) revert InvalidSignatureProvided();
        if (!isUnique) revert UserNotUnique();

        _userNonces[msg.sender]++;

        uint256 votingRights = ISciManager(sciManagerContract)
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
     * @dev Completes off-chain execution proposals. This function should only be called by admin
     * when the actual deliverables described in the proposal have been implemented, not just when
     * the governance process is complete. For example, if a proposal is to build a new product,
     * this should only be called when the product is actually built, not when the proposal passes.
     * @param index the _proposalIndex of the proposal of interest
     */
    function complete(
        uint256 index
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
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
        uint256 endIndex = _proposalIndex;

        for (uint256 i = 0; i < endIndex; i++) {
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
     * @dev Returns the set action type limit
     */
    function getActionTypeLimit() external view returns (uint256) {
        return _actionTypeLimit;
    }

    /**
     * @dev Returns the operations proposal _proposalIndex
     */
    function getProposalIndex() external view returns (uint256) {
        return _proposalIndex;
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
     * @dev Returns the factory address
     */
    function getFactory() external view returns (address) {
        return address(_factory);
    }

    /**
     * @dev Returns the _signer address. Is a DAO-controlled address.
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

    /**
     * @dev Returns the current nonce for a user
     * @param user The address of the user
     */
    function getUserNonce(address user) external view returns (uint256) {
        return _userNonces[user];
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
     * @dev Calculates a keccak256 hash for the given parameters.
     * @param user The user's Ethereum address.
     * @param isUnique Boolean flag representing whether the user's status is unique.
     * @param nonce The user's current nonce.
     * @param timestamp The timestamp when the signature was created.
     * @param proposalIndex The index of the proposal being voted on.
     */
    function _getMessageHash(
        address user,
        bool isUnique,
        uint256 nonce,
        uint256 timestamp,
        uint256 proposalIndex
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    user,
                    isUnique,
                    nonce,
                    timestamp,
                    proposalIndex
                )
            );
    }

    /**
     * @dev Verifies if a given signature is valid for the specified parameters.
     *      Requires the signature to be signed off-chain by the DAO-controlled signer.
     *      External call to Holonym's SBT balance of the user is deprecated.
     *      Holonym's SBTs are only on Optimism and Near not on Base, hence the current approach.
     * @param user The address of the user to verify.
     * @param isUnique Boolean flag to check along with the user address.
     * @param timestamp The timestamp when the signature was created.
     * @param proposalIndex The index of the proposal being voted on.
     * @param signature The signature to verify.
     */
    function _verify(
        address user,
        bool isUnique,
        uint256 timestamp,
        uint256 proposalIndex,
        bytes memory signature
    ) internal view returns (bool) {
        // Check timestamp validity
        if (
            timestamp + SIGNATURE_VALIDITY_PERIOD < block.timestamp ||
            timestamp > block.timestamp
        ) {
            return false;
        }

        bytes32 messageHash = _getMessageHash(
            user,
            isUnique,
            _userNonces[user],
            timestamp,
            proposalIndex
        );
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
            uint256 oldStreak = _votingStreak[msg.sender];
            uint256 newStreak;

            if (index > 0 && _userVoteData[msg.sender][index - 1].voted) {
                newStreak = _votingStreak[msg.sender] >=
                    governanceParams.maxVotingStreak
                    ? governanceParams.maxVotingStreak
                    : _votingStreak[msg.sender] + 1;
            } else {
                newStreak = 1;
            }

            _votingStreak[msg.sender] = newStreak;
            emit VotingStreakUpdated(msg.sender, oldStreak, newStreak);
            voteData.votingStreakAtVote = newStreak;
        }

        voteData.voted = true;
        voteData.previousSupport = support;
        voteData.previousVoteAmount = actualVotes;

        if (voteData.initialVoteTimestamp == 0) {
            voteData.initialVoteTimestamp = block.timestamp;
        }

        _latestVoteTimestamp[msg.sender] = block.timestamp;

        ISciManager(sciManagerContract).voted(
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
