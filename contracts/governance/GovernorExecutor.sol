// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

contract GovernorExecutor is AccessControl {
    error AlreadyScheduled(address action);
    error CannotBeZero();
    error NotScheduled(address action);
    error TooEarly(uint256 currentTime, uint256 scheduledTime);
    error ExecutionFailed();

    uint256 public delay;
    address public admin;
    address public governor;
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    mapping(address => uint256) public scheduledTime;

    event SetNewAdmin(address indexed user, address indexed newAddress);
    event SetNewGovernor(address indexed user, address indexed newAddress);
    event SetNewDelay(uint256 oldDelay, uint256 newDelay);

    constructor(address admin_, uint256 delay_, address governor_) {
        if (admin_ == address(0) || delay_ == 0 || governor_ == address(0))
            revert CannotBeZero();
        delay = delay_;
        admin = admin_;
        governor = governor_;
        _setupRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /**
     * @dev Updates the treasury wallet address and transfers admin role.
     * @param newAdmin The address to be set as the new treasury wallet.
     */
    function setAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldAdmin = admin;
        admin = newAdmin;
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        emit SetNewAdmin(oldAdmin, newAdmin);
    }

    /**
     * @dev Updates the governor address and transfers admin role.
     * @param newGovernor The address to be set as the new governor.
     */
    function setGovernor(
        address newGovernor
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldGovernor = governor;
        governor = newGovernor;
        _grantRole(GOVERNOR_ROLE, newGovernor);
        _revokeRole(GOVERNOR_ROLE, oldGovernor);
        emit SetNewGovernor(oldGovernor, newGovernor);
    }

    /**
     * @dev Sets a new delay for scheduling actions.
     * @param newDelay The new delay in seconds.
     * @notice Only users with DEFAULT_ADMIN_ROLE can call this function.
     */
    function setDelay(uint256 newDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDelay == 0) revert CannotBeZero();
        uint256 oldDelay = delay;
        delay = newDelay;
        emit SetNewDelay(oldDelay, newDelay);
    }

    /**
     * @dev Schedules an action for execution after a delay.
     * @param action The address of the action to schedule.
     * @notice Only users with GOVERNOR_ROLE can call this function.
     */
    function schedule(address action) external onlyRole(GOVERNOR_ROLE) {
        if (scheduledTime[action] != 0) {
            revert AlreadyScheduled(action);
        }
        scheduledTime[action] = block.timestamp + delay;
    }

    /**
     * @dev Cancels a scheduled action.
     * @param action The address of the action to cancel.
     * @notice Only users with GOVERNOR_ROLE can call this function.
     */
    function cancel(address action) external onlyRole(GOVERNOR_ROLE) {
        if (scheduledTime[action] == 0) {
            revert NotScheduled(action);
        }
        scheduledTime[action] = 0;
    }

    /**
     * @dev Executes a scheduled action.
     * @param action The address of the action to execute.
     * @notice Only users with GOVERNOR_ROLE can call this function.
     */
    function execution(address action) external onlyRole(GOVERNOR_ROLE) {
        uint256 scheduled = scheduledTime[action];
        if (scheduled == 0) {
            revert NotScheduled(action);
        }
        if (block.timestamp < scheduled) {
            revert TooEarly(block.timestamp, scheduled);
        }

        scheduledTime[action] = 0;
        (bool success, ) = action.call(abi.encodeWithSignature("execute()"));
        if (!success) {
            revert ExecutionFailed();
        }
    }
}
