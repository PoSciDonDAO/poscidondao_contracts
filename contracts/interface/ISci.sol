// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

interface ISci {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}