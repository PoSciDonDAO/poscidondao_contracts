// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorAddDelegate {
    function addDelegate(address newDelegate) external;
}

contract AddDelegate is ReentrancyGuard, AccessControl {

    IGovernorAddDelegate staking;
    address targetWallet;
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    constructor(
        address targetWallet_,
        address govExecAddress_,
        address stakingAddress_
    ) {
        staking = IGovernorAddDelegate(stakingAddress_);
        targetWallet = targetWallet_;
        _grantRole(EXECUTOR_ROLE, govExecAddress_);
    }

    /**
     * @dev Execute the proposal to add a delegate
     */
    function execute() external nonReentrant onlyRole(EXECUTOR_ROLE) {
        staking.addDelegate(targetWallet);
    }
}
