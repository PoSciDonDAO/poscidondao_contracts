// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorRoleGrant {
    function grantDueDiligenceRole(address[] memory members) external;
    function checkExecutorRole(address member) external returns(bool);
}

contract Election is ReentrancyGuard, AccessControl {

    error IsNotExecutor(address contractAddress);

    IGovernorRoleGrant govRes;
    address[] targetWallets;
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    constructor(
        address[] memory targetWallets_,
        address govExecAddress_,
        address govResAddress_
    ) {
        govRes = IGovernorRoleGrant(govResAddress_);
        targetWallets = targetWallets_;
        _grantRole(EXECUTOR_ROLE, govExecAddress_);
    }

    /**
     * @dev Execute the proposal to elect a scientist
     */
    function execute() external nonReentrant onlyRole(EXECUTOR_ROLE) {
        bool isExecutor = govRes.checkExecutorRole(address(this));
        if(!isExecutor) revert IsNotExecutor(address(this));
        govRes.grantDueDiligenceRole(targetWallets);
    }
}
