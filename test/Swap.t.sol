// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Sci.sol";
import "contracts/exchange/Swap.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/test/MockWeth.sol";

contract SwapTest is Test {
    MockUsdc public usdc;
    MockWeth public weth;

    Sci public sci;
    Swap public swap;

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

        usdc = new MockUsdc(10000000e6);
        weth = new MockWeth(10000000e18);
        sci = new Sci(treasuryWallet);
        swap = new Swap(
            treasuryWallet,
            address(sci),
            address(usdc)
        );
        deal(address(sci), treasuryWallet, 100000000e18);
        sci.approve(address(swap), 10000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        usdc.approve(address(swap), 10000000e6);
        weth.approve(address(swap), 10000000e18);
        deal(address(weth), addr1, 10000e18);
        deal(addr1, 10000000e18);
        deal(address(usdc), addr1, 1000000e6);
        vm.stopPrank();
    }

    function testSwapUsdcSuccess() public {
        uint256 amount = 10000e6;
        uint256 expectedSciAmount = (amount * 10000) / swap.rateUsdc() * 1e12;

        vm.startPrank(addr1);
        usdc.approve(address(swap), amount);
        swap.swapUsdc(amount);

        assertEq(usdc.balanceOf(treasuryWallet), 10000e6);
        assertEq(
            sci.balanceOf(addr1),
            expectedSciAmount,
            "User SCI balance should increase"
        );

        vm.stopPrank();
    }

    function testSwapEthSuccess() public {
        uint256 amount = 1e18; 
        uint256 expectedSciAmount = (amount * 10000) / swap.rateEth();

        vm.startPrank(addr1);
        swap.swapEth{value: amount}();

        assertEq(
            address(treasuryWallet).balance,
            1e18,
            "Treasury ETH balance should increase"
        );
        assertEq(
            sci.balanceOf(addr1),
            expectedSciAmount,
            "User SCI balance should increase"
        );

        vm.stopPrank();
    }
}
