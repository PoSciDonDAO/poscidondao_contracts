// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Sci.sol";

contract SciTest is Test {

    Sci public sci;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address dao = vm.addr(6);
    address treasuryWallet = vm.addr(7);
    address govRes = vm.addr(8);

    function setUp() public {
        vm.startPrank(treasuryWallet);

            sci = new Sci(
                treasuryWallet
            );

        vm.stopPrank();
    }

    function test_InitialMinting() public {
        uint256 expectedBalance = 1891000 * 10 ** sci.decimals();
        uint256 actualBalance = sci.balanceOf(treasuryWallet);
        assertEq(actualBalance, expectedBalance, "Initial minting to the treasury wallet is incorrect");
    }

    function test_MintTokens() public {
        vm.startPrank(treasuryWallet);
            sci.mint(treasuryWallet, 1000000e18);
            assertEq(sci.totalSupply(), sci.balanceOf(treasuryWallet));
        vm.stopPrank();
    }

    function test_BurnTokens() public {
        vm.startPrank(treasuryWallet);
            sci.mint(treasuryWallet, 1000000e18);
            sci.burn(1000000e18);
            assertEq(sci.totalSupply(), sci.balanceOf(treasuryWallet));
        vm.stopPrank();
    }
}