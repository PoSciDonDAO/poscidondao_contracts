// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

interface IGovernorOperations {
    function hasDelegateeVotedOnActiveProposals(
        address delegator,
        address delegatee
    ) external view returns (bool);
}
