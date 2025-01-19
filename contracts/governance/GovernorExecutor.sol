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
    error NotScheduled(address action);
    error SameAddress();
    error TooEarly(uint256 currentTime, uint256 scheduledTime);

    uint256 public delay;
    uint256 public minimumDelay;
    address public admin;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    mapping(address => uint256) public scheduledTime;

    event AdminSet(address indexed user, address indexed newAddress);
    event Canceled(address indexed action);
    event DelayUpdated(uint256 newDelay);
    event Executed(address indexed action);
    event GovernorAdded(address indexed user, address indexed newGovernor);
    event GovernorRemoved(address indexed user, address indexed formerGovernor);
    event Scheduled(address indexed action);
    event MinimumDelayUpdated(uint256 newMinimumDelay);

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

        if (delay_ == 0) {
            revert CannotBeZero();
        }

        minimumDelay = 12 hours;
        delay = delay_;
        admin = admin_;

        _grantRole(GOVERNOR_ROLE, govOps_);
        _grantRole(GOVERNOR_ROLE, govRes_);
        _grantRole(GOVERNOR_ROLE, address(this));

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /**
     * @dev Update delay time
     * @param newDelay the updated time between proposal scheduling and execution
     */
    function updateDelay(
        uint56 newDelay
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDelay < minimumDelay) revert DelayTooShort();
        delay = newDelay;
        emit DelayUpdated(newDelay);
    }

    /**
     * @dev Sets the minimum delay for the delay function
     * @param newMinimumDelay the new minimum delay
     */
    function setMinimumDelay(
        uint256 newMinimumDelay
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minimumDelay = newMinimumDelay;
        emit MinimumDelayUpdated(newMinimumDelay);
    }

    /**
     * @dev Updates the admin address and transfers admin role.
     * @param newAdmin_ The address to be set as the new admin.
     */
    function setAdmin(address newAdmin_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin_ == address(0)) revert CannotBeZeroAddress();
        if (newAdmin_ == msg.sender) revert SameAddress();

        address oldAdmin = admin;
        admin = newAdmin_;
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin_);
        emit AdminSet(oldAdmin, newAdmin_);
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
     * @dev Cancels a scheduled action.
     * @param action The address of the action to cancel.
     */
    function cancel(
        address action
    ) external nonReentrant onlyRole(GOVERNOR_ROLE) {
        if (scheduledTime[action] == 0) {
            revert NotScheduled(action);
        }
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
}
