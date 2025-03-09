// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISciManager} from "contracts/interfaces/ISciManager.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "./../interfaces/IGovernorExecution.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title SciManager
 * @dev Manages SCI token operations including locking and unlocking tokens and delegating voting power.
 */
contract SciManager is ISciManager, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    ///*** ERRORS ***///
    error CannotBeZero();
    error CannotBeZeroAddress();
    error CannotClaim();
    error CannotLockDuringEmergency();
    error CannotLockMoreThanTotalSupply();
    error IncorrectBlockNumber();
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error NoPendingAdmin();
    error NotAContract(address);
    error NotPendingAdmin(address caller);
    error SameAddress();
    error TokensStillLocked(uint256 voteLockEndStamp, uint256 currentTimeStamp);
    error Unauthorized(address user);

    ///*** TOKEN ***//
    IERC20 private _sci;

    ///*** STRUCTS ***///
    struct User {
        uint256 lockedSci; //SCI deposited
        uint256 votingRights; //Voting rights for operation proposals
        uint256 proposeLockEnd; //Time before token unlock after proposing
        uint256 voteLockEnd; //Time before token unlock after voting
        uint256 amtSnapshots; //Amount of snapshots
        mapping(uint256 => Snapshot) snapshots; //Index => snapshot
    }

    struct Snapshot {
        uint256 atBlock;
        uint256 rights;
    }

    ///*** STORAGE & MAPPINGS ***///
    // Constants
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    uint256 public constant TOTAL_SUPPLY_SCI = 18910000e18; //never changes

    // Public state variables
    address public admin;
    bool public emergency = false;
    address public govOpsContract;
    address public govResContract;
    address public pendingAdmin;

    // Private state variables
    IGovernorExecution private _govExec;
    uint256 private _totLocked;

    // Public mappings
    mapping(address => User) public users;

    ///*** MODIFIERS ***///

    modifier onlyExecutor() {
        if (!_govExec.hasRole(EXECUTOR_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyGov() {
        if (!(msg.sender == govOpsContract || msg.sender == govResContract))
            revert Unauthorized(msg.sender);
        _;
    }

    ///*** EVENTS ***///
    event AdminSet(address indexed user, address indexed newAddress);
    event AdminTransferAccepted(address indexed oldAdmin, address indexed newAdmin);
    event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
    event EmergencySet(bool indexed emergency, uint256 timestamp);
    event Freed(address indexed user, address indexed asset, uint256 amount);
    event GovExecSet(address indexed user, address indexed newAddress);
    event GovOpsSet(address indexed user, address indexed newAddress);
    event GovResSet(address indexed user, address indexed newAddress);
    event Locked(address indexed user, address indexed asset, uint256 amount);
    event ProposeLockEndTimeUpdated(address user, uint256 proposeLockEndTime);
    event SciUpdated(address indexed user, address indexed newAddress);
    event Snapshotted(
        address indexed owner,
        uint256 votingRights,
        uint256 indexed blockNumber
    );
    event VoteLockEndTimeUpdated(address user, uint256 voteLockEndTime);

    constructor(address admin_, address sci_) {
        if (admin_ == address(0) || sci_ == address(0)) {
            revert CannotBeZeroAddress();
        }
        admin = admin_;
        _sci = IERC20(sci_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev Overrides the renounceRole function to prevent renouncing the admin role.
     * @param role The role being renounced
     * @param account The account renouncing the role
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        if (role == DEFAULT_ADMIN_ROLE) {
            revert Unauthorized(msg.sender);
        }
        super.renounceRole(role, account);
    }

    /**
     * @dev Initiates the transfer of admin role to a new address.
     * The new admin must accept the role by calling acceptAdmin().
     * @param newAdmin The address to be set as the pending admin.
     */
    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert CannotBeZeroAddress();
        if (newAdmin == msg.sender) revert SameAddress();
        if (newAdmin == pendingAdmin) revert SameAddress();
        
        pendingAdmin = newAdmin;
        emit AdminTransferInitiated(msg.sender, newAdmin);
    }

    /**
     * @dev Accepts the admin role transfer. Can only be called by the pending admin.
     */
    function acceptAdmin() external {
        if (pendingAdmin == address(0)) revert NoPendingAdmin();
        if (msg.sender != pendingAdmin) revert NotPendingAdmin(msg.sender);

        address oldAdmin = admin;
        admin = pendingAdmin;
        pendingAdmin = address(0);

        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        emit AdminTransferAccepted(oldAdmin, admin);
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
        emit GovExecSet(msg.sender, newGovExec);
    }

    /**
     * @dev Sets the governance operations contract address.
     * @param newGovOps Address of the new governance operations.
     */
    function setGovOps(
        address newGovOps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovOps == address(0)) revert CannotBeZeroAddress();
        if (newGovOps == address(govOpsContract)) revert SameAddress();

        uint256 size;
        assembly {
            size := extcodesize(newGovOps)
        }
        if (size == 0) revert NotAContract(newGovOps);

        govOpsContract = newGovOps;
        emit GovOpsSet(msg.sender, newGovOps);
    }

    /**
     * @dev sets the GovernorResearch contract address
     */
    function setGovRes(
        address newGovRes
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovRes == address(0)) revert CannotBeZeroAddress();
        if (newGovRes == address(govResContract)) revert SameAddress();
        uint256 size;
        assembly {
            size := extcodesize(newGovRes)
        }
        if (size == 0) revert NotAContract(newGovRes);

        govResContract = newGovRes;
        emit GovResSet(msg.sender, newGovRes);
    }

    /**
     * @dev Sets the SCI token address and interface
     * @param sci_ the address of the SCI token
     */
    function setSciToken(address sci_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (sci_ == address(0)) revert CannotBeZeroAddress();
        if (sci_ == address(_sci)) revert SameAddress();

        uint256 size;
        assembly {
            size := extcodesize(sci_)
        }
        if (size == 0) revert NotAContract(sci_);
        _sci = IERC20(sci_);
        emit SciUpdated(msg.sender, sci_);
    }

    /**
     * @dev locks a given amount of SCI tokens
     * @param amount the amount of tokens that will be locked
     */
    function lock(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert CannotBeZero();
        }
        if (emergency) {
            revert CannotLockDuringEmergency();
        }

        if (_totLocked + amount > TOTAL_SUPPLY_SCI) {
            revert CannotLockMoreThanTotalSupply();
        }

        uint256 balanceBefore = IERC20(_sci).balanceOf(address(this));

        IERC20(_sci).safeTransferFrom(msg.sender, address(this), amount);

        uint256 balanceAfter = IERC20(_sci).balanceOf(address(this));

        uint256 actualAmount = balanceAfter - balanceBefore;

        users[msg.sender].lockedSci += actualAmount;

        _totLocked += actualAmount;

        users[msg.sender].votingRights += actualAmount;

        _snapshot(msg.sender, users[msg.sender].votingRights);

        emit Locked(msg.sender, address(_sci), actualAmount);
    }

    /**
     * @dev frees locked tokens after vote or proposal lock end has passed
     * @param amount the amount of tokens that will be freed
     */
    function free(uint256 amount) external nonReentrant {
        if (
            (users[msg.sender].voteLockEnd > block.timestamp ||
                users[msg.sender].proposeLockEnd > block.timestamp) &&
            !emergency
        ) {
            revert TokensStillLocked(
                users[msg.sender].voteLockEnd,
                block.timestamp
            );
        }

        if (amount == 0) {
            revert CannotBeZero();
        }

        if (users[msg.sender].lockedSci < amount) {
            revert InsufficientBalance(users[msg.sender].lockedSci, amount);
        }

        users[msg.sender].lockedSci -= amount;

        IERC20(_sci).safeTransfer(msg.sender, amount);

        if (_totLocked < amount) {
            revert InsufficientBalance(_totLocked, amount);
        }

        _totLocked -= amount;

        if (users[msg.sender].votingRights < amount) {
            revert InsufficientBalance(users[msg.sender].votingRights, amount);
        }
        users[msg.sender].votingRights -= amount;

        _snapshot(msg.sender, users[msg.sender].votingRights);

        emit Freed(msg.sender, address(_sci), amount);
    }

    /**
     * @dev toggles the `emergency` state, which overrides vote and propose locks.
     */
    function setEmergency() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        emergency = !emergency;
        emit EmergencySet(emergency, block.timestamp);
    }

    /**
     * @dev is called by gov contracts upon voting
     * @param user the user's address holding SCI tokens
     * @param voteLockEnd the timestamp until which the tokens will be locked due to voting
     */
    function voted(
        address user,
        uint256 voteLockEnd
    ) external onlyGov returns (bool) {
        if (users[user].voteLockEnd < voteLockEnd) {
            users[user].voteLockEnd = voteLockEnd;
            emit VoteLockEndTimeUpdated(user, voteLockEnd);
        }

        return true;
    }

    /**
     * @dev is called by gov contracts upon proposing
     * @param user the user's address holding SCI tokens
     * @param proposeLockEnd the timestamp until which the tokens will be locked due to proposing
     */
    function proposed(
        address user,
        uint256 proposeLockEnd
    ) external onlyGov returns (bool) {
        if (users[user].proposeLockEnd < proposeLockEnd) {
            users[user].proposeLockEnd = proposeLockEnd;
            emit ProposeLockEndTimeUpdated(user, proposeLockEnd);
        }
        return true;
    }

    /**
     * @dev returns the user rights from the latest taken snapshot
     * @param user the user address
     */
    function getLatestUserRights(address user) external view returns (uint256) {
        uint256 latestSnapshotIndex = users[user].amtSnapshots;
        return getUserRights(user, latestSnapshotIndex, block.number);
    }

    /**
     * @dev returns the SCI token contract address
     */
    function getSciAddress() external view returns (address) {
        return address(_sci);
    }

    /**
     * @dev returns the total amount of locked SCI tokens
     */
    function getTotalLockedSci() external view returns (uint256) {
        return _totLocked;
    }

    /**
     * @dev returns the amount of locked SCI tokens of a given user
     */
    function getLockedSci(address user) external view returns (uint256) {
        return users[user].lockedSci;
    }

    /**
     * @dev returns the propose lock end time
     */
    function getProposeLockEnd(address user) external view returns (uint256) {
        return users[user].proposeLockEnd;
    }

    /**
     * @dev returns the vote lock end time
     */
    function getVoteLockEnd(address user) external view returns (uint256) {
        return users[user].voteLockEnd;
    }

    ///*** PUBLIC FUNCTION ***///

    /**
     * @dev Return the voting rights of a user at a certain snapshot
     * @param user the user address
     * @param snapshotIndex the index of the snapshots the user has
     * @param blockNum the highest block.number at which the user rights will be retrieved
     */
    function getUserRights(
        address user,
        uint256 snapshotIndex,
        uint256 blockNum
    ) public view returns (uint256) {
        uint256 index = users[user].amtSnapshots;
        if (snapshotIndex > index) revert IncorrectSnapshotIndex();
        Snapshot memory snap = users[user].snapshots[snapshotIndex];
        if (snap.atBlock > blockNum) revert IncorrectBlockNumber();
        return snap.rights;
    }

    ///*** INTERNAL FUNCTIONS ***///

    /**
     * @dev a snaphshot of the current voting rights of a given user
     * @param user the address that is being snapshotted
     */
    function _snapshot(address user, uint256 votingRights) internal {
        uint256 index = users[user].amtSnapshots;
        if (index > 0 && users[user].snapshots[index].atBlock == block.number) {
            users[user].snapshots[index].rights = votingRights;
        } else {
            users[user].amtSnapshots = index += 1;
            users[user].snapshots[index] = Snapshot(block.number, votingRights);
        }
        emit Snapshotted(user, votingRights, block.number);
    }
}
