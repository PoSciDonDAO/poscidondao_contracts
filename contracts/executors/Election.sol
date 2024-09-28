// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorRoleGrant {
    function grantDueDiligenceRole(address[] memory members) external;
}

contract Election is ReentrancyGuard, AccessControl {
    IGovernorRoleGrant govRes;
    address[] targetWallets;
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    constructor(
        address[] memory targetWallets_,
        address govExecAddress_,
        address govResAddress_
    ) {
        govRes = IGovernorRoleGrant(govResAddress_);
        targetWallets = targetWallets_;
        _grantRole(GOVERNOR_ROLE, govExecAddress_);
    }

    /**
     * @dev Execute the proposal to impeach a scientist
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        govRes.grantDueDiligenceRole(targetWallets);
    }
}
