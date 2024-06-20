// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

interface IGovernorResearch {
    function grantDueDiligenceRole(address member) external;
    function revokeDueDiligenceRole(address member) external;
    function DUE_DILIGENCE_ROLE() external returns(bytes32);
}