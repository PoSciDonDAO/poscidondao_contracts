// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IActionCloneFactory {
    function createAction(uint256 actionType, bytes memory params) external returns (address);
}