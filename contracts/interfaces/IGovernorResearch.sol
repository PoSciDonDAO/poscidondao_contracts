// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

interface IGovernorResearch {
    function grantDueDiligenceRole(address member) external;

    function revokeDueDiligenceRole(address member) external;

    function checkDueDiligenceRole(address member) external returns (bool);
}
