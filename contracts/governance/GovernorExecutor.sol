// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * @title GovernorExecutor
 * @dev Handles execution of proposals.
 */
contract GovernorExecutor is AccessControl, ReentrancyGuard {
    error AlreadyScheduled(address action);
    error AddressIsNotGovernor();
    error CannotBeZero();
    error CannotBeZeroAddress();
    error DelayTooShort();
    error ExecutionFailed();
    error GovernorNotFound(address governor);
    error GovernorAlreadyExists(address governor);
    error NoPendingAdmin();
    error NotPendingAdmin(address caller);
    error NotScheduled(address action);
    error SameAddress();
    error TooEarly(uint256 currentTime, uint256 scheduledTime);
    error Unauthorized(address user);

    uint256 public delay;
    address public admin;
    address public pendingAdmin;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    mapping(address => uint256) public scheduledTime;

    event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferAccepted(address indexed oldAdmin, address indexed newAdmin);
    event Canceled(address indexed action);
    event DelaySet(uint256 newDelay);
    event Executed(address indexed action);
    event GovernorAdded(address indexed user, address indexed newGovernor);
    event GovernorRemoved(address indexed user, address indexed formerGovernor);
    event Scheduled(address indexed action);

    constructor(
        address admin_,
        uint256 delay_,
        address govOps_,
        address govRes_
    ) {
        if (
            admin_ == address(0) ||
            govOps_ == address(0) ||
            govRes_ == address(0)
        ) revert CannotBeZeroAddress();

        if (delay_ < 1 hours || delay_ > 7 days) revert DelayTooShort();
        delay = delay_;
        admin = admin_;

        _grantRole(GOVERNOR_ROLE, govOps_);
        _grantRole(GOVERNOR_ROLE, govRes_);
        _grantRole(GOVERNOR_ROLE, address(this));

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /**
     * @dev Sets delay time
     * @param newDelay the time between proposal scheduling and execution
     */
    function setDelay(
        uint56 newDelay
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDelay < 1 hours || newDelay > 7 days) revert DelayTooShort();
        delay = newDelay;
        emit DelaySet(newDelay);
    }

    /**
     * @dev Adds a new governor to the list.
     * @param newGovernor The address to be added as a new governor.
     */
    function addGovernor(
        address newGovernor
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (hasRole(GOVERNOR_ROLE, newGovernor))
            revert GovernorAlreadyExists(newGovernor);

        _grantRole(GOVERNOR_ROLE, newGovernor);

        emit GovernorAdded(msg.sender, newGovernor);
    }

    /**
     * @dev Adds a new governor to the list.
     * @param formerGovernor The address to be added as a new governor.
     */
    function removeGovernor(
        address formerGovernor
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!hasRole(GOVERNOR_ROLE, formerGovernor))
            revert GovernorAlreadyExists(formerGovernor);

        _revokeRole(GOVERNOR_ROLE, formerGovernor);

        emit GovernorRemoved(msg.sender, formerGovernor);
    }

    /**
     * @dev Schedules an action for execution after a delay.
     * @param action The address of the action to schedule.
     */
    function schedule(
        address action
    ) external nonReentrant onlyRole(GOVERNOR_ROLE) {
        if (scheduledTime[action] != 0) {
            revert AlreadyScheduled(action);
        }
        scheduledTime[action] = block.timestamp + delay;
        emit Scheduled(action);
    }

    /**
     * @dev Cancels an action.
     * @param action The address of the action to cancel.
     */
    function cancel(
        address action
    ) external nonReentrant onlyRole(GOVERNOR_ROLE) {
        scheduledTime[action] = 0;
        emit Canceled(action);
    }

    /**
     * @dev Executes a scheduled action with a temporary `EXECUTOR_ROLE`.
     *      This role needed to call functions such as setGovernanceParameters
     *      and grantDueDiligenceRole in GovernorOperations and GovernorResearch.
     * @param action The address of the action to execute.
     */
    function execution(
        address action
    ) external nonReentrant onlyRole(GOVERNOR_ROLE) {
        if (action == address(0)) revert CannotBeZeroAddress();
        
        uint256 scheduled = scheduledTime[action];
        if (scheduled == 0) {
            revert NotScheduled(action);
        }
        if (scheduled > block.timestamp) {
            revert TooEarly(block.timestamp, scheduled);
        }

        scheduledTime[action] = 0;

        _grantRole(EXECUTOR_ROLE, action);

        bool success;
        {
            (success, ) = action.call(abi.encodeWithSignature("execute()"));
        }

        _revokeRole(EXECUTOR_ROLE, action);

        if (!success) {
            revert ExecutionFailed();
        }

        emit Executed(action);
    }

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
}
