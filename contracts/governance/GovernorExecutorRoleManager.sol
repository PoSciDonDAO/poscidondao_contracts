// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title GovernorRoleManager
 * @dev Abstract contract for managing Governor Execution roles.
 */
abstract contract GovernorExecutorRoleManager is AccessControl {
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    event GovernorAdded(address indexed governor);
    event GovernorRemoved(address indexed governor);

    error CannotBeZeroAddress();

    /**
     * @dev Checks if address has executor role.
     * @param executor The address to check for the EXECUTOR_ROLE.
     * @return True if the address has the EXECUTOR_ROLE.
     */
    function checkExecutorRole(address executor) public view returns (bool) {
        return hasRole(EXECUTOR_ROLE, executor);
    }

    /**
     * @dev Sets the Governor Execution addresses in batch.
     * @param newGovernorAddresses An array of new Governor Execution addresses.
     */
    function addExecutors(address[] memory newGovernorAddresses) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < newGovernorAddresses.length; i++) {
            address newGovernorAddress = newGovernorAddresses[i];
            if (newGovernorAddress == address(0)) revert CannotBeZeroAddress();

            // Grant the EXECUTOR_ROLE to the new governor
            _grantRole(EXECUTOR_ROLE, newGovernorAddress);

            // Emit event for each new governor added
            emit GovernorAdded(newGovernorAddress);
        }
    }

    /**
     * @dev Removes the Governor Execution addresses in batch.
     * @param formerGovernorAddresses An array of Governor Execution addresses to remove.
     */
    function removeExecutors(address[] memory formerGovernorAddresses) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < formerGovernorAddresses.length; i++) {
            address formerGovernorAddress = formerGovernorAddresses[i];
            if (formerGovernorAddress == address(0)) revert CannotBeZeroAddress();

            // Revoke the EXECUTOR_ROLE from the governor
            _revokeRole(EXECUTOR_ROLE, formerGovernorAddress);

            // Emit event for each removed governor
            emit GovernorRemoved(formerGovernorAddress);
        }
    }
}
