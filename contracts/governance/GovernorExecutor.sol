// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

contract GovernorExecutor is AccessControl, ReentrancyGuard {
    error AlreadyScheduled(address action);
    error CannotBeZero();
    error NotScheduled(address action);
    error TooEarly(uint256 currentTime, uint256 scheduledTime);
    error ExecutionFailed();
    error GovernorNotFound(address governor);
    error GovernorAlreadyExists(address governor);

    uint256 public delay;
    address public admin;
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    // Use a mapping to track governor addresses
    mapping(address => bool) public governors;

    mapping(address => uint256) public scheduledTime;

    event SetNewAdmin(address indexed user, address indexed newAddress);
    event SetNewGovernor(address indexed user, address indexed newGovernor);
    event RemovedGovernor(address indexed user, address removedGovernor);
    event SetNewDelay(uint256 oldDelay, uint256 newDelay);

    constructor(
        address admin_,
        uint256 delay_,
        address[] memory governorAddresses_
    ) {
        if (admin_ == address(0) || delay_ == 0 || governorAddresses_.length == 0) revert CannotBeZero();

        delay = delay_;
        admin = admin_;

        for (uint256 i = 0; i < governorAddresses_.length; i++) {
            governors[governorAddresses_[i]] = true;
            _setupRole(GOVERNOR_ROLE, governorAddresses_[i]);
        }

        _setupRole(DEFAULT_ADMIN_ROLE, admin_);
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
     * @dev Adds a new governor to the list.
     * @param newGovernor The address to be added as a new governor.
     */
    function addGovernor(address newGovernor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (governors[newGovernor]) revert GovernorAlreadyExists(newGovernor);
        governors[newGovernor] = true;
        _grantRole(GOVERNOR_ROLE, newGovernor);
        emit SetNewGovernor(msg.sender, newGovernor);
    }

    /**
     * @dev Removes a governor from the list of governor addresses.
     * @param governorToRemove The address of the governor to remove.
     */
    function removeGovernor(address governorToRemove) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!governors[governorToRemove]) revert GovernorNotFound(governorToRemove);
        governors[governorToRemove] = false;
        _revokeRole(GOVERNOR_ROLE, governorToRemove);
        emit RemovedGovernor(msg.sender, governorToRemove);
    }

    /**
     * @dev Sets a new delay for scheduling actions.
     * @param newDelay The new delay in seconds.
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
     */
    function schedule(address action) external nonReentrant onlyRole(GOVERNOR_ROLE) {
        if (scheduledTime[action] != 0) {
            revert AlreadyScheduled(action);
        }
        scheduledTime[action] = block.timestamp + delay;
    }

    /**
     * @dev Cancels a scheduled action.
     * @param action The address of the action to cancel.
     */
    function cancel(address action) external nonReentrant onlyRole(GOVERNOR_ROLE) {
        if (scheduledTime[action] == 0) {
            revert NotScheduled(action);
        }
        scheduledTime[action] = 0;
    }

    /**
     * @dev Executes a scheduled action.
     * @param action The address of the action to execute.
     */
    function execution(address action) external nonReentrant onlyRole(GOVERNOR_ROLE) {
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

    /**
     * @dev Checks if an address is a governor.
     * @param governor The address to check.
     * @return bool True if the address is a governor, otherwise false.
     */
    function isGovernor(address governor) external view returns (bool) {
        return governors[governor];
    }
}
