// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorCancel {
    function cancel(uint256 id) external;
}

/**
 * @title GovernorGuard
 * @dev Allows admin to cancel malicious proposals
 */
contract GovernorGuard is AccessControl {
    address public admin;
    IGovernorCancel public govOps;
    IGovernorCancel public govRes;

    event SetNewAdmin(address indexed user, address indexed newAdmin);

    error CannotBeZeroAddress();
    error ProposalAlreadyDropped(uint256 id);

    constructor(address admin_, address govOps_, address govRes_) {
        if (
            admin_ == address(0) ||
            govOps_ == address(0) ||
            govRes_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }
        admin = admin_;
        govOps = IGovernorCancel(govOps_);
        govRes = IGovernorCancel(govRes_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
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
    function cancelOps(uint256 id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        try govOps.cancel(id) {
        } catch {
            revert ProposalAlreadyDropped(id);
        }
    }

        /**
     * @dev Drops a proposal by calling the drop function on the Governor contract.
     * @param id The ID of the proposal to drop.
     * @notice Only the admin can call this function.
     */
    function cancelRes(uint256 id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        try govRes.cancel(id) {
        } catch {
            revert ProposalAlreadyDropped(id);
        }
    }
}
