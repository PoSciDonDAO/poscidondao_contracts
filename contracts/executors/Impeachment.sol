// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorRoleRevoke {
    function revokeDueDiligenceRole(address[] memory members) external;
    function checkExecutorRole(address member) external returns(bool);
}

contract Impeachment is ReentrancyGuard, AccessControl {

    // error IsNotExecutor(address contractAddress);

    IGovernorRoleRevoke govRes;
    address[] targetWallets;
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    constructor(
        address[] memory targetWallets_,
        address govExecAddress_,
        address govResAddress_
    ) {
        govRes = IGovernorRoleRevoke(govResAddress_);
        targetWallets = targetWallets_;
        _grantRole(EXECUTOR_ROLE, govExecAddress_);
    }

    /**
     * @dev Execute the proposal to elect a scientist
     */
    function execute() external nonReentrant onlyRole(EXECUTOR_ROLE) {
        // bool isExecutor = govRes.checkExecutorRole(address(this));
        // if(!isExecutor) revert IsNotExecutor(address(this));
        govRes.revokeDueDiligenceRole(targetWallets);
    }
}
