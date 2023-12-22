//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IParticipation {
    function balanceOf(address participant) external view returns (uint256);
    function push(address user, uint256 amount) external;
    function pull(address user, uint256 amount) external;
    function mint(address participant) external;
}