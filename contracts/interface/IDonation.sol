//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDonation {
    function push(address user, uint256 amount) external;
    function pull(address user, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}