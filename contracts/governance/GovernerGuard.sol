// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorLike {
    function drop(uint256 id) external;
}

contract GovernorGuard is AccessControl {
    address public admin;
    IGovernorLike public governor;

    event SetNewAdmin(address indexed user, address indexed newAdmin);
    event SetNewGovernor(address indexed user, address indexed newGovernor);

    // *** ERRORS *** //
    error ProposalAlreadyDropped(uint256 id);

    constructor(address admin_, address governor_) {
        admin = admin_;
        governor = IGovernorLike(governor_);

        // Grant the initial admin role to the deployer
        _setupRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /**
     * @dev Updates the admin address and transfers admin role.
     * @param newAdmin_ The address to be set as the new admin.
     */
    function setAdmin(address newAdmin_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldAdmin = admin;
        admin = newAdmin_;
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin_);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        emit SetNewAdmin(oldAdmin, newAdmin_);
    }

    /**
     * @dev Drops a proposal by calling the drop function on the Governor contract.
     * @param id The ID of the proposal to drop.
     * @notice Only the admin can call this function.
     */
    function cancel(uint256 id) external {
        try governor.drop(id) {
        } catch {
            revert ProposalAlreadyDropped(id);
        }
    }
}
