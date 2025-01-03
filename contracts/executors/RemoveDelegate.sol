// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface ISciManagerRemoveDelegate {
    function removeDelegate(address formerDelegate) external;
}

/**
 * @title RemoveDelegate
 * @dev Handles the removal of a delegate selected by the DAO.
 */
contract RemoveDelegate is ReentrancyGuard, AccessControl {
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
     * @dev Execute the proposal to remove a delegate
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        ISciManagerRemoveDelegate(sciManager).removeDelegate(targetWallet);
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
        emit ActionExecuted(address(this), "RemoveDelegate");
    }
}
