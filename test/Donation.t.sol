// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Donation.sol";
import "contracts/test/Token.sol";
import "contracts/staking/Staking.sol";

contract DonationTest is Test {

    Donation public don;
    Token public usdc;
    Staking public staking;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address dao = vm.addr(6);
    address donationWallet = vm.addr(7);
    address treasuryWallet = vm.addr(8);
    address stakingContract = vm.addr(9);
    address po = vm.addr(10);
    address sci = vm.addr(11);

    event DonationCompleted(address indexed user, uint256 donation, uint256 tokenAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {

        usdc = new Token(10000000e18);
        usdc.transfer(addr1, 100000e18);
        usdc.transfer(addr2, 100000e18);

        vm.startPrank(dao);
            don = new Donation(
                address(usdc),
                donationWallet,
                treasuryWallet
            );
            staking = new Staking(
                address(don),
                dao
            );
        vm.stopPrank();

        vm.startPrank(addr1);
            usdc.approve(address(don), 10000e18);
            vm.deal(addr1, 10 ether);
        vm.stopPrank();

        vm.startPrank(addr2);
            usdc.approve(address(don), 10000e18);
            vm.deal(addr2, 10000000 ether);
        vm.stopPrank();

        vm.startPrank(addr3);
            usdc.approve(address(don), 10000e18);
            vm.deal(addr2, 10000000 ether);
        vm.stopPrank();

        vm.startPrank(addr4);
            usdc.approve(address(don), 10000e18);
            vm.deal(addr2, 10000000 ether);
        vm.stopPrank();

        vm.startPrank(dao);
            don.setStakingContract(address(staking));
            usdc.approve(address(don), 10000e18);
        vm.stopPrank();
    }

    function test_addAndRemoveGov() public {
        vm.startPrank(dao);
            don.addWard(addr4);
        vm.stopPrank();
        assertEq(don.wards(addr4), 1);

        vm.startPrank(dao);
            don.removeWard(addr4);
        vm.stopPrank();
        assertEq(don.wards(addr4), 0);
    }

    function test_ReturnStakingContract() public {
        assertEq(don.stakingContract(), address(staking));
    }

    function test_Revert_If_UnauthorizedSetsStakingContract() public {
        vm.startPrank(addr1);
            bytes4 selector = bytes4(keccak256("Unauthorized(address)"));
            vm.expectRevert(abi.encodeWithSelector(selector, addr1));
            don.setStakingContract(address(staking));
        vm.stopPrank();
    }

    function test_DonateUsdc() public {
        vm.startPrank(addr2);
        don.donateUsdc(addr2, 1000e6);
        assertEq(usdc.balanceOf(donationWallet), 950e6);
        assertEq(usdc.balanceOf(treasuryWallet), 50e6);
        assertEq(don.balanceOf(addr2), 1000e18);
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
        assertEq(don.balanceOf(addr2), 180000e18);
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
        assertEq(don.balanceOf(addr2), 1800000000e18);
        assertEq(donationWallet.balance, 950000 ether);
        assertEq(treasuryWallet.balance, 50000 ether);
        vm.stopPrank();
    }

    function test_DonateEtherMintEvent() public {
        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);
        emit DonationCompleted(addr2, 1e18, 1800e18);
        don.donateEth{value: 1 ether}(addr2);
        vm.stopPrank();
    }

    function test_DonateUsdcMintEvent() public {
        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);
        emit DonationCompleted(addr2, 1000e6, 1000e18);
        don.donateUsdc(addr2, 1000e6);
        vm.stopPrank();
    }
}