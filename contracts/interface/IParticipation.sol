// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

interface IParticipation {
    function balanceOf(address user) external view returns (uint256);
    function push(address user, uint256 amount) external;
    function pull(address user, uint256 amount) external;
    function mint(address user) external;
    function burn(address user, uint256 amount) external;
}