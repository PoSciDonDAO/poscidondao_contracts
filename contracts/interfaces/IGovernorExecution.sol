// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

interface IGovernorExecution {

    /**
     * @dev Schedules an action for execution after a delay.
     * @param action The address of the action to schedule.
     */
    function schedule(address action) external;

    /**
     * @dev Cancels a scheduled action.
     * @param action The address of the action to cancel.
     */
    function cancel(address action) external;

    /**
     * @dev Executes a scheduled action.
     * @param action The address of the action to execute.
     */
    function execution(address action) external;

    /**
     * @dev Returns the scheduled time for a specific action.
     * @param action The address of the action to check.
     * @return Returns the time the action is scheduled for.
     */
    function scheduledTime(address action) external view returns (uint256);
}
