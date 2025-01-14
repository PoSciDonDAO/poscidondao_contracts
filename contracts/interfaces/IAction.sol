// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IAction {
    function initialize(bytes memory params) external;
    function execute() external;
}