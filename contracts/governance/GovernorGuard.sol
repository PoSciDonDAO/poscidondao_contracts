// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorCancel {
    function cancel(uint256 id) external;
}

/**
 * @title GovernorGuard
 * @dev Allows admin to cancel malicious proposals
 */
contract GovernorGuard is AccessControl {
    error CannotBeZeroAddress();
    error NoPendingAdmin();
    error NotPendingAdmin(address caller);
    error ProposalAlreadyDropped(uint256 id);
    error SameAddress();
    error Unauthorized(address user);

    address public admin;
    address public pendingAdmin;
    IGovernorCancel public govOps;
    IGovernorCancel public govRes;

    event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferAccepted(address indexed oldAdmin, address indexed newAdmin);

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

    /**
     * @dev Drops a proposal by calling the drop function on the Governor contract.
     * @param id The ID of the proposal to drop.
     * @notice Only the admin can call this function.
     */
    function cancelOps(uint256 id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        try govOps.cancel(id) {} catch {
            revert ProposalAlreadyDropped(id);
        }
    }

    /**
     * @dev Drops a proposal by calling the drop function on the Governor contract.
     * @param id The ID of the proposal to drop.
     * @notice Only the admin can call this function.
     */
    function cancelRes(uint256 id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        try govRes.cancel(id) {} catch {
            revert ProposalAlreadyDropped(id);
        }
    }
}
