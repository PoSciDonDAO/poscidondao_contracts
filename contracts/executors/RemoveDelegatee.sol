// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface ISciManagerRemoveDelegatee {
    function removeDelegatee(address formerDelegatee) external;
}

/**
 * @title RemoveDelegatee
 * @dev Handles the removal of a Delegatee selected by the DAO.
 */
contract RemoveDelegatee is ReentrancyGuard, AccessControl {
    address public targetWallet;
    address public sciManager;
    address public governorExecutor;
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    event ActionExecuted(address indexed action, string indexed contractName);

    constructor(
        address targetWallet_,
        address governorExecutor_,
        address sciManager_
    ) {
        sciManager = sciManager_;
        targetWallet = targetWallet_;
        governorExecutor = governorExecutor_;
        _grantRole(GOVERNOR_ROLE, governorExecutor_);
    }

    /**
     * @dev Execute the proposal to remove a Delegatee
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        ISciManagerRemoveDelegatee(sciManager).removeDelegatee(targetWallet);
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
        emit ActionExecuted(address(this), "RemoveDelegatee");
    }
}
