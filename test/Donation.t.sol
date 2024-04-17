// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/donating/Donation.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/test/MockWeth.sol";

contract DonationTest is Test {

    Donation public don;
    MockUsdc public usdc;
    MockWeth public weth;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address dao = vm.addr(6);
    address donationWallet = vm.addr(7);
    address treasuryWallet = vm.addr(8);

    event DonationCompleted(address indexed user, address asset, uint256 donation);

    function setUp() public {

        usdc = new MockUsdc(10000000e6);
        weth = new MockWeth(10000000e18);

        vm.startPrank(dao);
            don = new Donation(
                donationWallet,
                treasuryWallet,
                address(usdc),
                address(weth)
            );
        vm.stopPrank();

        vm.startPrank(addr1);
            usdc.approve(address(don), 10000e6);
            weth.approve(address(don), 10000e18);
            deal(addr1, 10000000e18);
            deal(address(usdc), addr1, 10000e6);
            deal(address(weth), addr1, 10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            usdc.approve(address(don), 10000e6);
            weth.approve(address(don), 10000e18);
            deal(addr2, 10000000e18);
            deal(address(usdc), addr2, 10000e6);
            deal(address(weth), addr2, 10000e18);
        vm.stopPrank();

        vm.startPrank(dao);
            usdc.approve(address(don), 10000e6);
        vm.stopPrank();
    }

    function test_DonateUsdc() public {
        vm.startPrank(addr2);
            don.donateUsdc(1000e6);
            assertEq(usdc.balanceOf(donationWallet), 950e6);
            assertEq(usdc.balanceOf(treasuryWallet), 50e6);
        vm.stopPrank();
    }

    function test_DonateUsdcMintEvent() public {
        vm.startPrank(addr2);
            vm.expectEmit(true, true, true, true);
            emit DonationCompleted(addr2, address(usdc), 1000e6);
            don.donateUsdc(1000e6);
        vm.stopPrank();
    }

    function test_RevertIfThresholdDonateUsdcNotReached() public {
        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("InsufficientDonation()"));
            vm.expectRevert(selector);
            don.donateUsdc(1e5);
        vm.stopPrank();
    }

    function test_DonateMatic() public {
        vm.startPrank(addr2);
            don.donateMatic{value: 100e18}();
            assertEq(donationWallet.balance, 95e18);
            assertEq(treasuryWallet.balance, 5e18);
        vm.stopPrank();
    }

    function test_DonateWeth() public {
        vm.startPrank(addr2);
            don.donateWeth(1000e18);
            assertEq(weth.balanceOf(donationWallet), 950e18);
            assertEq(weth.balanceOf(treasuryWallet), 50e18);
        vm.stopPrank();
    }
    
    function test_RevertIfThresholdDonateMaticNotReached() public {
        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("InsufficientDonation()"));
            vm.expectRevert(selector);
            don.donateMatic{value: 0.00001e18}();
        vm.stopPrank();
    }

    function test_DonateHighMaticAmount() public {
        vm.startPrank(addr2);
            don.donateMatic{value: 1000000e18}();
            assertEq(donationWallet.balance, 950000e18);
            assertEq(treasuryWallet.balance, 50000e18);
        vm.stopPrank();
    }

    function test_donateMaticMintEvent() public {
        vm.startPrank(addr2);
            vm.expectEmit(true, true, true, true);
            emit DonationCompleted(addr2, address(0), 1e18);
            don.donateMatic{value: 1e18}();
        vm.stopPrank();
    }
}