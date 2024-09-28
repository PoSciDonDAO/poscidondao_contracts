// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

interface IGovernorResearchRevoke {
    function revokeDueDiligenceRole(address[] memory members) external;
}

contract Impeachment is ReentrancyGuard {
   IGovernorResearchRevoke govRes;
    address[] targetWallets;

    constructor(address[] memory targetWallets_, address govResAddress) {
        govRes =IGovernorResearchRevoke(govResAddress);
        targetWallets = targetWallets_;
    }

    /**
     * @dev Execute the proposal to impeach a scientist
     */
    function execute() external nonReentrant {
        govRes.revokeDueDiligenceRole(targetWallets);
    }
}
