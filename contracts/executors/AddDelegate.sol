// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorAddDelegate {
    function addDelegate(address newDelegate) external;
}

/**
 * @title AddDelegate
 * @dev Handles the addition of delegates selected by the DAO.
 */
contract AddDelegate is ReentrancyGuard, AccessControl {
    address public targetWallet;
    address public sciManager;
    address public governorExecutor;
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    event ActionExecuted(address indexed action, string indexed contractName);

    constructor(
        address targetWallet_,
        address governorExecutor_,
        address staking_
    ) {
        sciManager = staking_;
        targetWallet = targetWallet_;
        governorExecutor = governorExecutor_;
        _grantRole(GOVERNOR_ROLE, governorExecutor_);
    }

    /**
     * @dev Execute the proposal to add a delegate
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        IGovernorAddDelegate(sciManager).addDelegate(targetWallet);
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
        emit ActionExecuted(address(this), "AddDelegate");
    }
}
