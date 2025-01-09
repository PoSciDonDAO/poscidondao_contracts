// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IGovernorOperations {
    function canDelegateVotingPower(address user) external view returns (bool);
}
