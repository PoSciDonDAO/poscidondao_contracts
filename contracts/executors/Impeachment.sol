// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorRoleRevoke {
    function revokeDueDiligenceRole(address[] memory members) external;
    function checkDueDiligenceRole(address member) external returns (bool);
}

/**
 * @title Impeachment
 * @dev Manages the impeachment of scientists that govern the research funding process.
 */
contract Impeachment is ReentrancyGuard, AccessControl {
    error CannotBeZeroAddress();
    error AddressHasNotDDRole();

    address[] internal _targetWallets;
    address public governorResearch;
    address public governorExecutor;
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    event ActionExecuted(address indexed action, string indexed contractName);

    constructor(
        address[] memory targetWallets_,
        address governorResearch_,
        address governorExecutor_
    ) {
        if (
            governorResearch_ == address(0) || governorExecutor_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }
        for (uint256 i = 0; i < targetWallets_.length; i++) {
            if (targetWallets_[i] == address(0)) {
                revert CannotBeZeroAddress();
            }
            if (
                !IGovernorRoleRevoke(governorResearch_).checkDueDiligenceRole(
                    targetWallets_[i]
                )
            ) {
                revert AddressHasNotDDRole();
            }
        }
        _targetWallets = targetWallets_;
        governorResearch = governorResearch_;
        governorExecutor = governorExecutor_;
        _grantRole(GOVERNOR_ROLE, governorExecutor);
    }

    /**
     * @dev Returns all elected wallets
     */
    function getAllImpeachedWallets() public view returns (address[] memory) {
        return _targetWallets;
    }

    /**
     * @dev Execute the proposal to elect a scientist
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        IGovernorRoleRevoke(governorResearch).revokeDueDiligenceRole(
            _targetWallets
        );
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
        emit ActionExecuted(address(this), "Impeachment");
    }
}
