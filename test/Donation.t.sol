// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/donating/Donation.sol";
import "contracts/test/MockUsdc.sol";

contract DonationTest is Test {

    Donation public don;
    MockUsdc public usdc;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address dao = vm.addr(6);
    address donationWallet = vm.addr(7);
    address treasuryWallet = vm.addr(8);

    event DonationCompleted(address indexed user, uint256 donation);

    function setUp() public {

        usdc = new MockUsdc(10000000e6);

        vm.startPrank(dao);
            don = new Donation(
                address(usdc),
                donationWallet,
                treasuryWallet
            );
        vm.stopPrank();

        vm.startPrank(addr1);
            usdc.approve(address(don), 10000e6);
            deal(addr1, 10000000 ether);
            deal(address(usdc), addr1, 10000e6);
        vm.stopPrank();

        vm.startPrank(addr2);
            usdc.approve(address(don), 10000e6);
            deal(addr2, 10000000 ether);
            deal(address(usdc), addr2, 10000e6);
        vm.stopPrank();

        vm.startPrank(addr3);
            usdc.approve(address(don), 10000e6);
            deal(addr3, 10000000 ether);
            deal(address(usdc), addr3, 10000e6);
        vm.stopPrank();

        vm.startPrank(addr4);
            usdc.approve(address(don), 10000e6);
            deal(addr3, 10000000 ether);
            deal(address(usdc), addr4, 10000e6);
        vm.stopPrank();

        vm.startPrank(dao);
            usdc.approve(address(don), 10000e6);
        vm.stopPrank();
    }

    function test_DonateUsdc() public {
        vm.startPrank(addr2);
            don.donateUsdc(addr2, 1000e6);
            assertEq(usdc.balanceOf(donationWallet), 950e6);
            assertEq(usdc.balanceOf(treasuryWallet), 50e6);
        vm.stopPrank();
    }

    function test_DonateUsdcMintEvent() public {
        vm.startPrank(addr2);
            vm.expectEmit(true, true, true, true);
            emit DonationCompleted(addr2, 1000e6);
            don.donateUsdc(addr2, 1000e6);
        vm.stopPrank();
    }

    function test_RevertIfThresholdDonateUsdcNotReached() public {
        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("InsufficientDonation()"));
            vm.expectRevert(selector);
            don.donateUsdc(addr2, 1e5);
        vm.stopPrank();
    }

    function test_DonateEther() public {
        vm.startPrank(addr2);
            don.donateEth{value: 100 ether}(addr2);
            assertEq(donationWallet.balance, 95 ether);
            assertEq(treasuryWallet.balance, 5 ether);
        vm.stopPrank();
    }
    
    function test_RevertIfThresholdDonateEtherNotReached() public {
        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("InsufficientDonation()"));
            vm.expectRevert(selector);
            don.donateEth{value: 0.00001 ether}(addr2);
        vm.stopPrank();
    }

    function test_DonateHighEtherAmount() public {
        vm.startPrank(addr2);
            don.donateEth{value: 1000000 ether}(addr2);
            assertEq(donationWallet.balance, 950000 ether);
            assertEq(treasuryWallet.balance, 50000 ether);
        vm.stopPrank();
    }

    function test_DonateEtherMintEvent() public {
        vm.startPrank(addr2);
            vm.expectEmit(true, true, true, true);
            emit DonationCompleted(addr2, 1 ether);
            don.donateEth{value: 1 ether}(addr2);
        vm.stopPrank();
    }
}