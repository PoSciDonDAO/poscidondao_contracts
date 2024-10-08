// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Usdc is ERC20 {
    uint8 private _decimals;

    constructor(
        uint256 amount_
    ) ERC20("USD Coin", "USDC") {
        _decimals = 6;
        _mint(0x690BF2dB31D39EE0a88fcaC89117b66a588E865a, amount_);
    }

    function mint(address _to, uint256 _amount) public returns (bool) {
        _mint(_to, _amount);
        return true;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}