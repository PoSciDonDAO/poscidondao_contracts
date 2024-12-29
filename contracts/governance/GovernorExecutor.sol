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
    error ExecutionFailed();
    error GovernorNotFound(address governor);
    error GovernorAlreadyExists(address governor);
    error NotScheduled(address action);
    error TooEarly(uint256 currentTime, uint256 scheduledTime);

    uint256 public delay;
    address public admin;
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    mapping(address => uint256) public scheduledTime;

    event Canceled(address indexed action);
    event DelayUpdated(uint256 newDelay);
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

        if(delay_ == 0) {
            revert CannotBeZero();
        }

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
    function updateDelay(uint56 newDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delay = newDelay;
        emit DelayUpdated(newDelay);
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

        _grantRole(GOVERNOR_ROLE, formerGovernor);

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

        _grantRole(EXECUTOR_ROLE, action);

        (bool success, ) = action.call(abi.encodeWithSignature("execute()"));
        if (!success) {
            revert ExecutionFailed();

        }
        scheduledTime[action] = 0;

        _revokeRole(EXECUTOR_ROLE, action);
        
        emit Executed(action);
    }
}
