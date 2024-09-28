// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

interface IGovernorParams {
    function setGovParams(bytes32 param, uint256 data) external;
}

contract GovernorParameters is ReentrancyGuard {
    IGovernorParams gov;

    bytes32 param;
    uint256 data;

    constructor(address govAddress_, bytes32 param_, uint256 data_) {
        gov = IGovernorParams(govAddress_);
        param = param_;
        data = data_;
    }

    /**
     * @dev Execute the proposal to elect a scientist
     */
    function execute() external nonReentrant {
        gov.setGovParams(param, data);
    }
}
