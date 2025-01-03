// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface ISciManagerAddDelegate {
    function addDelegate(address newDelegate) external;
    function getCurrentDelegatee(
        address delegator
    ) external view returns (address);
}

/**
 * @title AddDelegate
 * @dev Handles the addition of a delegate selected by the DAO.
 */
contract AddDelegate is ReentrancyGuard, AccessControl {
    error CannotBeZeroAddress();
    error DelegatorCannotBeDelegatee();

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
        if (
            targetWallet_ == address(0) ||
            governorExecutor_ == address(0) ||
            sciManager_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }
        sciManager = sciManager_;
        targetWallet = targetWallet_;
        governorExecutor = governorExecutor_;
        _grantRole(GOVERNOR_ROLE, governorExecutor_);
    }

    /**
     * @dev Execute the proposal to add a delegate
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        address currentDelegatee = ISciManagerAddDelegate(sciManager)
            .getCurrentDelegatee(targetWallet);
        if (currentDelegatee != address(0)) {
            revert DelegatorCannotBeDelegatee();
        }
        ISciManagerAddDelegate(sciManager).addDelegate(targetWallet);
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
        emit ActionExecuted(address(this), "AddDelegate");
    }
}
