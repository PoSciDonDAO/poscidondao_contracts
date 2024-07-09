// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Sci.sol";
import "contracts/exchange/Swap.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/test/MockWeth.sol";

contract SwapTest is Test {
    MockUsdc public usdc;

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
        sci = new Sci(treasuryWallet);
        swap = new Swap(treasuryWallet, address(sci), address(usdc));
        deal(address(sci), treasuryWallet, 100000000e18);
        sci.approve(address(swap), 10000000e18);
        address[] memory whitelist = new address[](2);
        whitelist[0] = addr1;
        whitelist[1] = addr2;
        swap.addMembersToWhitelist(whitelist);
        vm.stopPrank();

        vm.startPrank(addr1);
        usdc.approve(address(swap), 10000000e6);
        deal(addr1, 10000000 ether);
        deal(address(usdc), addr1, 1000000e6);
        vm.stopPrank();

        vm.startPrank(addr3);
        usdc.approve(address(swap), 10000000e6);
        deal(addr3, 10000000 ether);
        deal(address(usdc), addr3, 1000000e6);
        vm.stopPrank();
    }

    function testSwapUsdcSuccess() public {
        uint256 amount = 10000e6;
        uint256 expectedSciAmount = ((amount * 10000) / swap.rateUsdc()) * 1e12;

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
        uint256 expectedSciAmount = amount * swap.rateEth();

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

    function testRevertSwapUsdcNotWhitelisted() public {
        uint256 amount = 10000e6;

        vm.startPrank(addr3);
        usdc.approve(address(swap), amount);
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        swap.swapUsdc(amount);
        vm.stopPrank();
    }

    function testRevertSwapEthNotWhitelisted() public {
        uint256 amount = 1e18;

        vm.startPrank(addr3);
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        swap.swapEth{value: amount}();
        vm.stopPrank();
    }

    function testRevertSwapUsdcSaleExpired() public {
        uint256 amount = 10000e6;

        vm.startPrank(addr1);
        usdc.approve(address(swap), amount);
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(abi.encodeWithSignature("SaleExpired()"));
        swap.swapUsdc(amount);
        vm.stopPrank();
    }

    function testRevertSwapEthSaleExpired() public {
        uint256 amount = 1e18;

        vm.startPrank(addr1);
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(abi.encodeWithSignature("SaleExpired()"));
        swap.swapEth{value: amount}();
        vm.stopPrank();
    }

    function testRevertSwapUsdcSoldOut() public {
        uint256 cap = swap.sciSwapCap();
        uint256 largeAmountUsdc = (cap * swap.rateUsdc()) / 10000 + 1e18;

        vm.startPrank(addr1);
        usdc.approve(address(swap), largeAmountUsdc);
        vm.expectRevert(abi.encodeWithSignature("SoldOut()"));
        swap.swapUsdc(largeAmountUsdc); 
        vm.stopPrank();
    }

    function testRevertSwapEthSoldOut() public {
        uint256 cap = swap.sciSwapCap();
        uint256 largeAmountEth = cap / swap.rateEth() + 5 ether;
        vm.startPrank(addr1);
        vm.expectRevert(abi.encodeWithSignature("SoldOut()"));
        swap.swapEth{value: largeAmountEth}();
        vm.stopPrank();
    }
}
