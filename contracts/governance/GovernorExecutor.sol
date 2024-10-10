// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

contract GovernorExecutor is AccessControl, ReentrancyGuard {
    error AlreadyScheduled(address action);
    error AddressIsNotGovernor();
    error CannotBeZero();
    error NotScheduled(address action);
    error TooEarly(uint256 currentTime, uint256 scheduledTime);
    error ExecutionFailed();
    error GovernorNotFound(address governor);
    error GovernorAlreadyExists(address governor);

    uint256 public delay;
    address public admin;
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    mapping(address => uint256) public scheduledTime;

    event SetNewAdmin(address indexed user, address indexed newAddress);
    event SetNewGovernor(address indexed user, address indexed newGovernor);
    event RemovedGovernor(address indexed user, address removedGovernor);
    event SetNewDelay(uint256 oldDelay, uint256 newDelay);

    constructor(
        address admin_,
        uint256 delay_,
        address govOps_,
        address govRes_
    ) {
        if (
            admin_ == address(0) ||
            delay_ == 0 ||
            govOps_ == address(0) ||
            govRes_ == address(0)
        ) revert CannotBeZero();

        delay = delay_;
        admin = admin_;

        _setupRole(GOVERNOR_ROLE, govOps_);
        _setupRole(GOVERNOR_ROLE, govRes_);
        _setupRole(GOVERNOR_ROLE, address(this));

        _setupRole(DEFAULT_ADMIN_ROLE, admin_);
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
        emit SetNewGovernor(msg.sender, newGovernor);
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
        emit SetNewGovernor(msg.sender, formerGovernor);
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
    }
}
