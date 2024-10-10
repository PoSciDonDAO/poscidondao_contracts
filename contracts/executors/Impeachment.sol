// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorRoleRevoke {
    function revokeDueDiligenceRole(address[] memory members) external;
}

contract Impeachment is ReentrancyGuard, AccessControl {

    address[] public targetWallets;
    address public governorResearch;
    address public governorExecutor; 
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    constructor(
        address[] memory targetWallets_,
        address governorResearch_,
        address governorExecutor_
    ) {
        targetWallets = targetWallets_;
        governorResearch = governorResearch_;
        governorExecutor = governorExecutor_;
        _grantRole(GOVERNOR_ROLE, governorExecutor);
    }

    /**
     * @dev Execute the proposal to elect a scientist
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        IGovernorRoleRevoke(governorResearch).revokeDueDiligenceRole(targetWallets);
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
    }
}
