//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IParticipation {
    function getHeldBalance(address participant) external view returns (uint256[] memory);
    function push(address user, uint256 amount) external;
    function pull(address user, uint256 amount) external;
    function mint(address participant) external;
}