// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Sci.sol";
import "contracts/tokens/Voucher.sol";
import "contracts/exchange/VoucherToSciConversion.sol";
import "contracts/test/Usdc.sol";
import "contracts/DeployedAddresses.sol";
import "contracts/DeployedPresaleAddresses.sol";

contract VoucherToSciConversionTest is Test {
    Usdc usdc;

    Sci sci;
    Voucher voucher;
    VoucherToSciConversion conversion;

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
        voucher = Voucher(DeployedPresaleAddresses.voucher);
        conversion = VoucherToSciConversion(
            DeployedPresaleAddresses.voucherToSciConversion
        );
        sci.approve(address(conversion), 94550e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        deal(address(voucher), addr1, 100e18);
        vm.stopPrank();

        vm.startPrank(addr4);
        deal(address(voucher), addr1, 100e18);
        vm.stopPrank();
    }

    function testConversion() public {
        uint256 voucherBalanceBeforeConversion = voucher.balanceOf(addr1);
        uint256 sciBalanceBeforeConversion = sci.balanceOf(addr1);
        vm.startPrank(addr1);
        voucher.approve(address(conversion), voucherBalanceBeforeConversion);
        conversion.convert();
        uint256 sciBalanceAfterConversion = sci.balanceOf(addr1);
        assertEq(
            sciBalanceAfterConversion,
            sciBalanceBeforeConversion + voucherBalanceBeforeConversion
        );
        vm.stopPrank();
    }

    function testRevertConversionIfNotWhitelisted() public {
        vm.startPrank(addr4);
        uint256 voucherBalanceBeforeConversion = voucher.balanceOf(addr4);
        voucher.approve(address(conversion), voucherBalanceBeforeConversion);
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        conversion.convert();
        vm.stopPrank();
    }
}
