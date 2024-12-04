// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Sci.sol";
import "contracts/tokens/Voucher.sol";
import "contracts/exchange/ConvertWithRatio.sol";
import "contracts/test/Usdc.sol";
import "contracts/DeployedConversionAddresses.sol";

contract ConvertWithRatioTest is Test {
    Sci sci;
    Voucher voucher;
    ConvertWithRatio convert;

    address addr1 = 0x690BF2dB31D39EE0a88fcaC89117b66a588E865a;
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address admin = DeployedConversionAddresses.admin;

    function setUp() public {
        vm.startPrank(admin);
        sci = Sci(DeployedConversionAddresses.sci);
        voucher = Voucher(DeployedConversionAddresses.voucher);
        convert = ConvertWithRatio(
            DeployedConversionAddresses.convert
        );
        sci.approve(address(convert), 94550e18);
        vm.stopPrank();

        // vm.startPrank(addr1);
        // deal(address(voucher), addr1, 100e18);
        // vm.stopPrank();
        voucher.balanceOf(addr1);

        vm.startPrank(addr4);
        deal(address(voucher), addr4, 100e18);
        vm.stopPrank();
    }

    function test_ConvertWithRatio() public {
        vm.startPrank(addr1);
        uint256 voucherBalanceBeforeConversion = voucher.balanceOf(addr1);
        uint256 sciBalanceBeforeConversion = sci.balanceOf(addr1);

        voucher.approve(address(convert), voucherBalanceBeforeConversion);
        convert.convertWithRatio();
        uint256 sciBalanceAfterConversion = sci.balanceOf(addr1);
        assertEq(
            sciBalanceAfterConversion,
            sciBalanceBeforeConversion + (voucherBalanceBeforeConversion * convert.conversionRate() / 100000)
        );
        vm.stopPrank();
    }

    function test_RevertConversionWithLimitIfNotWhitelisted() public {
        vm.startPrank(addr4);
        uint256 voucherBalanceBeforeConversion = voucher.balanceOf(addr4);
        voucher.approve(address(convert), voucherBalanceBeforeConversion);
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        convert.convertWithRatio();
        vm.stopPrank();
    }
}
