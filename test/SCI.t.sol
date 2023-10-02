// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/tokens/SCI.sol";
import "contracts/test/Token.sol";

contract SCITest is Test {

    SCI public sci;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address dao = vm.addr(6);
    address treasuryWallet = vm.addr(8);
    address router = vm.addr(9);
    address govRes = vm.addr(10);

    function setUp() public {
        vm.startPrank(dao);

            sci = new SCI(
                treasuryWallet
            );

        vm.stopPrank();

        vm.startPrank(treasuryWallet);
            sci.transfer(addr1, 1000e18);
            sci.transfer(addr2, 1000e18);
            sci.transfer(addr3, 1000e18);
        vm.stopPrank();

    }

    function mintTokens() public {
        sci.mint(treasuryWallet, 1000000e18);
        assertEq(sci.totalSupply(), sci.balanceOf(treasuryWallet));
    }
}