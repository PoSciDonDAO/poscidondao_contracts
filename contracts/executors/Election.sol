// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorRoleGrant {
    function grantDueDiligenceRole(address[] memory members) external;
}

contract Election is ReentrancyGuard, AccessControl {

    address[] public targetWallets;
    address public governorResearch = 0xb4385384EF9DeB20b1EB91e78C088558eA4Fecea;
    address public governorExecutor = 0x4c80b5F7a85B5A6FeA00C7354cBE763e6B426e95;
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    constructor(
        address[] memory targetWallets_
    ) {

        targetWallets = targetWallets_;
        _grantRole(EXECUTOR_ROLE, governorExecutor);
    }

    /**
     * @dev Execute the proposal to elect a scientist
     */
    function execute() external nonReentrant onlyRole(EXECUTOR_ROLE) {
        IGovernorRoleGrant(governorResearch).grantDueDiligenceRole(targetWallets);
    }
}
