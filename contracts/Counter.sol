// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// simport "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Counter {
    uint256 public number;

    uint16 public number2;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function setNumber2(uint16 newNumber) public {
        number2 = newNumber;
    }

    function increment() public {
        number++;
    }
}
