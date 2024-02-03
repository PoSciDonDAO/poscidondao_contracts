//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISci {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}