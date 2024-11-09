// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Sci.sol";
import "contracts/exchange/Swap.sol";
import "contracts/test/Usdc.sol";
import "contracts/DeployedAddresses.sol";
import "contracts/DeployedSwapAddress.sol";

contract SwapTest is Test {
    Usdc usdc;

    Sci sci;
    Swap swap;

    address addr1 = 0x690BF2dB31D39EE0a88fcaC89117b66a588E865a;
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address admin = DeployedAddresses.admin;

    function setUp() public {

        usdc = Usdc(DeployedAddresses.usdc);
        vm.startPrank(admin);
        sci = Sci(DeployedAddresses.sci);
        swap = Swap(DeployedSwapAddress.swap);
        sci.approve(DeployedSwapAddress.swap, 94550e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        usdc.approve(address(swap), 10000000e6);
        deal(addr1, 10000000 ether);
        deal(address(usdc), addr1, 1000000e6);
        vm.stopPrank();

        vm.startPrank(addr4);
        usdc.approve(address(swap), 10000000e6);
        deal(addr4, 10000000 ether);
        deal(address(usdc), addr4, 1000000e6);
        vm.stopPrank();
    }

    function testSwapUsdcSuccess() public {
        uint256 oldBalanceAdmin = usdc.balanceOf(admin);
        uint256 oldBalanceAddr1 = sci.balanceOf(addr1);
        uint256 amount = swap.currentEtherPrice();
        uint256 expectedSciAmount = ((amount * 10000) / swap.priceInUsdc()) * 1e12;

        vm.startPrank(addr1);
        usdc.approve(address(swap), amount);
        swap.swapUsdc(amount);

        assertEq(usdc.balanceOf(admin), oldBalanceAdmin + amount);
        assertEq(
            sci.balanceOf(addr1),
            oldBalanceAddr1 + expectedSciAmount,
            "User SCI balance should increase"
        );

        vm.stopPrank();
    }

    function testSwapEthSuccess() public {
        uint256 oldBalanceAdmin = admin.balance;
        uint256 oldBalanceAddr1 = sci.balanceOf(addr1);

        uint256 amount = 1 ether;
        uint256 expectedSciAmount = amount * swap.ethToVoucherConversionRate();

        vm.startPrank(addr1);
        swap.swapEth{value: amount}();

        assertEq(
            address(admin).balance,
            oldBalanceAdmin + amount,
            "Treasury ETH balance should increase"
        );
        assertEq(
            sci.balanceOf(addr1),
            oldBalanceAddr1 + expectedSciAmount,
            "User SCI balance should increase"
        );

        vm.stopPrank();
    }

    function testRevertSwapUsdcNotWhitelisted() public {
        uint256 amount = 10000e6;

        vm.startPrank(addr4);
        usdc.approve(address(swap), amount);
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        swap.swapUsdc(amount);
        vm.stopPrank();
    }

    function testRevertSwapEthNotWhitelisted() public {
        uint256 amount = 1e18;

        vm.startPrank(addr4);
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        swap.swapEth{value: amount}();
        vm.stopPrank();
    }

    function testRevertSwapUsdcSaleExpired() public {
        vm.warp(block.timestamp);
        uint256 amount = 1000e6;

        vm.startPrank(addr1);
        usdc.approve(address(swap), amount);
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(abi.encodeWithSignature("SaleExpired()"));
        swap.swapUsdc(amount);
        vm.stopPrank();
    }

    function testRevertSwapEthSaleExpired() public {
        vm.warp(block.timestamp);
        uint256 amount = 1 ether;

        vm.startPrank(addr1);
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(abi.encodeWithSignature("SaleExpired()"));
        swap.swapEth{value: amount}();
        vm.stopPrank();
    }

    function testRevertSwapEthLimitReached() public {
        uint256 amount = 1.00001 ether;

        vm.startPrank(addr1);
        vm.expectRevert(abi.encodeWithSignature("CannotSwapMoreThanOneEther()"));
        swap.swapEth{value: amount}();
        vm.stopPrank();
    }

    function testRevertSwapUsdcLimitReached() public {
        uint256 amount = swap.currentEtherPrice() * 1e6 + 1e6;

        vm.startPrank(addr1);
        vm.expectRevert(abi.encodeWithSignature("CannotSwapMoreThanOneEther()"));
        swap.swapUsdc(amount);
        vm.stopPrank();
    }

    // function testRevertSwapEthSoldOut() public {
    //     uint256 cap = swap.sciSwapCap();
    //     uint256 largeAmountEth = cap / swap.rateEth();
    //     vm.startPrank(addr1);
    //     vm.expectRevert(abi.encodeWithSignature("SoldOut()"));
    //     swap.swapEth{value: largeAmountEth}();
    //     vm.stopPrank();
    // }
}
