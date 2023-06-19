// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/tokens/Donation.sol";
import "contracts/test/Token.sol";
import "contracts/governance/GovernorResearch.sol";

contract DonationTest is Test {

    Donation public don;
    Token public usdc;
    GovernorResearch public govRes;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address admin = vm.addr(6);
    address donationWallet = vm.addr(7);
    address govOps = vm.addr(9);
    address sci = vm.addr(10);

    event DonationCompleted(address indexed user, uint256 donation, uint256 tokenAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {

        usdc = new Token(10000000e18);
        usdc.transfer(addr1, 100000e18);
        usdc.transfer(addr2, 100000e18);

        vm.startPrank(admin);
            don = new Donation(
                address(usdc),
                donationWallet
            );
            govRes = new GovernorResearch(
                sci,
                address(don)
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

        vm.startPrank(admin);
            don.setGovRes(address(govRes));
            don.setGovOps(govOps);
            usdc.approve(address(don), 10000e18);
            don.ratioEth(16, 10);
            don.ratioUsdc(10, 10);
            don.setTreshold(1e15);
        vm.stopPrank();
    }

    function test_addAndRemoveGov() public {
        vm.startPrank(admin);
            don.addGov(addr4);
        vm.stopPrank();
        assertEq(don.govs(addr4), 1);

        vm.startPrank(admin);
            don.removeGov(addr4);
        vm.stopPrank();
        assertEq(don.govs(addr4), 0);
    }

    function test_SetAndReturnGovRes() public {
        vm.startPrank(admin);
            don.setGovRes(address(govRes));
        assertEq(don.govRes(), address(govRes));
        vm.stopPrank();
    }

    function test_SetAndReturnGovOps() public {
        vm.startPrank(admin);
            don.setGovOps(govOps);
        vm.stopPrank();
        assertEq(don.govOps(), govOps);
    }

    function test_RevertSettingGovOpsOrRes() public {
        vm.startPrank(addr1);
            bytes4 selector = bytes4(keccak256("Unauthorized(address)"));
            vm.expectRevert(abi.encodeWithSelector(selector, addr1));
            don.setGovOps(govOps);
        vm.stopPrank();

        vm.startPrank(addr1);
            bytes4 selector2 = bytes4(keccak256("Unauthorized(address)"));
            vm.expectRevert(abi.encodeWithSelector(selector2, addr1));
            don.setGovRes(address(govRes));
        vm.stopPrank();
    }

    function test_DonateUsdc() public {
        vm.startPrank(addr2);
        don.donateUsdc(addr2, 1000e18);
        assertEq(usdc.balanceOf(donationWallet), 1000e18);
        assertEq(don.balanceOf(addr2), 1000e18);
        vm.stopPrank();
    }

    function test_RevertTresholdDonateUsdc() public {
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("InsufficientDonation()"));
        vm.expectRevert(selector);
        don.donateUsdc(addr2, 1e14);
        vm.stopPrank();
    }

    function test_DonateEther() public {
        vm.startPrank(addr2);
        don.donateEth{value: 1 ether}(addr2);
        assertEq(don.balanceOf(addr2), 1600e18);
        assertEq(donationWallet.balance, 1 ether);
        vm.stopPrank();
    }
    
    function test_RevertTresholdDonateEther() public {
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("InsufficientDonation()"));
        vm.expectRevert(selector);
        don.donateEth{value: 0.00001 ether}(addr2);
        vm.stopPrank();
    }

    function test_DonateHighEtherAmount() public {
        vm.startPrank(addr2);
        don.donateEth{value: 1000000 ether}(addr2);
        assertEq(don.balanceOf(addr2), 1600000000e18);
        assertEq(donationWallet.balance, 1000000 ether);
        vm.stopPrank();
    }

    function test_DonateEtherMintEvent() public {
        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);
        emit DonationCompleted(addr2, 1e18, 1600e18);
        don.donateEth{value: 1 ether}(addr2);
        vm.stopPrank();
    }

    function test_DonateUsdcMintEvent() public {
        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);
        emit DonationCompleted(addr2, 1000e18, 1000e18);
        don.donateUsdc(addr2, 1000e18);
        vm.stopPrank();
    }

    function test_PushToGovRes() public {
        vm.startPrank(addr2);
            don.donateUsdc(addr2, 100e18);
            don.push(addr2, address(govRes), 90e18);
            assertEq(don.balanceOf(address(govRes)), 90e18);
        vm.stopPrank();
    }

    function test_PushToGovOps() public {
        vm.startPrank(addr2);
            don.donateUsdc(addr2, 100e18);
            don.push(addr2, govOps, 90e18);
            assertEq(don.balanceOf(govOps), 90e18);
        vm.stopPrank();
    }

    function test_PullFromGovOps() public {
        vm.startPrank(addr2);
            don.donateUsdc(addr2, 100e18);
            don.push(addr2, govOps, 100e18);
            assertEq(don.balanceOf(govOps), don.depositsGovOps(addr2));
            assertEq(don.balanceOf(addr2), 0);
            don.pull(govOps, addr2, 100e18);
            assertEq(don.balanceOf(addr2), 100e18);
        vm.stopPrank();
    }

    function test_PullFromGovRes() public {
        vm.startPrank(addr2);
            don.donateUsdc(addr2, 100e18);
            //lock
            don.push(addr2, address(govRes), 100e18);
            assertEq(don.balanceOf(address(govRes)), don.depositsGovRes(addr2));
            assertEq(don.balanceOf(addr2), 0);
            //free
            don.pull(address(govRes), addr2, 100e18);
            assertEq(don.balanceOf(addr2), 100e18);
        vm.stopPrank();
    }

    function test_RevertPullInsufficientDonation() public {
        vm.startPrank(addr2);
            don.donateUsdc(addr2, 100e18);
            //lock
            don.push(addr2, address(govRes), 100e18);
        vm.stopPrank();
        vm.startPrank(addr2);
            //free
            bytes4 selector = bytes4(keccak256("InsufficientDeposit()"));
            vm.expectRevert(selector);
            don.pull(address(govRes), addr2, 1000e18);
        vm.stopPrank();
    }

    function test_RevertPullAccountBound() public {
        vm.startPrank(addr2);
            don.donateUsdc(addr2, 100e18);
            don.push(addr2, address(govRes), 100e18);
        vm.stopPrank();
        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("AccountBound()"));
            vm.expectRevert(selector);
            don.pull(addr1, addr2, 100e18);
        vm.stopPrank();
    }
}