// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

interface IGovernorGuard {

    /**
     * @dev Cancels a proposal.
     * @param id The id of the proposal to cancel.
     */
    function cancel(uint256 id) external;
}
