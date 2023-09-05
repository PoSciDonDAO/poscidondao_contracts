// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/Donation.sol";
import "contracts/tokens/Trading.sol";
import "contracts/test/Token.sol";
import "contracts/staking/Staking.sol";

contract StakingTest is Test {

    Participation public po;
    Trading public sci;
    Donation public don;
    Token public usdc;
    Staking public staking;

    address public addr1 = vm.addr(1);
    address public addr2 = vm.addr(2);
    address public addr3 = vm.addr(3);
    address public addr4 = vm.addr(4);
    address public addr5 = vm.addr(5);
    address public dao = vm.addr(6);
    address public royaltyAddress = vm.addr(7);
    address public donationWallet = vm.addr(8);
    address public treasuryWallet = vm.addr(9);
    address public impactNftAddress = vm.addr(10);

    event Locked(address indexed user, address indexed gov, uint256 deposit, uint256 votes);
    event Freed(address indexed gov, address indexed user, uint256 amount, uint256 remainingVotes);


    function setUp() public {

        usdc = new Token(10000000e18);
        usdc.transfer(addr1, 10000e18);
        usdc.transfer(addr2, 10000e18);
        usdc.transfer(addr3, 1000e18);
        usdc.transfer(addr4, 1000e18);
        usdc.transfer(addr5, 1000e18);
        usdc.transfer(dao, 1000e18);

        vm.startPrank(dao);
            po = new Participation(
                "baseURI",
                dao
                // impactNftAddress
            );

            sci = new Trading(
                treasuryWallet
            );

            don = new Donation(
                address(usdc),
                donationWallet
            );

            staking = new Staking(
                address(po),
                address(sci), 
                address(don),
                dao
            );

            don.setStakingContract(address(staking));
        vm.stopPrank();

        vm.startPrank(addr1);
            usdc.approve(address(don), 1000000000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            usdc.approve(address(don), 1000000000e18);
        vm.stopPrank();

        deal(address(usdc), addr1, 10000e18);
        deal(address(usdc), addr2, 10000e18);
        deal(address(usdc), addr3, 10000e18);

        deal(address(sci), addr1, 100000000e18);
        deal(address(don), addr1, 100000000e18);

        deal(address(sci), addr2, 100000000e18);
        deal(address(don), addr2, 100000000e18);

        deal(address(sci), addr3, 100000000e18);
        deal(address(don), addr3, 100000000e18);

        vm.startPrank(addr1);
            sci.approve(address(staking), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            sci.approve(address(staking), 10000e18);
        vm.stopPrank();
    }

    function test_AddingAndRemovingGov() public {
        vm.startPrank(dao);
            staking.addGov(addr1);
            assertEq(staking.wards(addr1), 1);

            staking.removeGov(addr1);
            assertEq(staking.wards(addr1), 0);
        vm.stopPrank();
    }

    function test_LockSciTokens() public {
        vm.startPrank(addr1);
            staking.lock(address(sci), addr1, 500e18);

            (
            uint256 stakedPo,
            uint256 stakedSci, 
            uint256 stakedDon, 
            uint256 votingRights, 
            uint256 voteLockTime, 
            uint256 amtSnapshots
            ) = staking.users(addr1);

            assertEq(stakedPo, 0);
            assertEq(stakedSci, sci.balanceOf(address(staking)));
            assertEq(stakedDon, 0);
            assertEq(votingRights, 500e18);
            assertEq(voteLockTime, 0);
            assertEq(amtSnapshots, 1);
            
        vm.stopPrank();
    }

    function test_LockDonTokens() public {
        vm.startPrank(addr1);
            staking.lock(address(don), addr1, 500e18);

            (
            uint256 stakedPo,
            uint256 stakedSci, 
            uint256 stakedDon, 
            uint256 votingRights, 
            uint256 voteLockTime, 
            uint256 amtSnapshots
            ) = staking.users(addr1);

            assertEq(staking.getTotalStaked(), 500e18);
            assertEq(stakedPo, 0);
            assertEq(stakedSci, 0);
            assertEq(stakedDon, 500e18);
            assertEq(votingRights, 500e18);
            assertEq(voteLockTime, 0);
            assertEq(amtSnapshots, 1);
            
        vm.stopPrank();
    }

    function test_EmitLockEventWithDonTokens() public {
        vm.startPrank(addr1);
            vm.expectEmit(true, true, true, true);

            emit Locked(address(don), addr1, 100e18, 100e18);

            staking.lock(address(don), addr1, 100e18);
        vm.stopPrank();
    }

    function test_EmitLockEventWithSciTokens() public {
        vm.startPrank(addr2);
            vm.expectEmit(true, true, true, true);

            emit Locked(address(sci), addr2, 100e18, 100e18);

            staking.lock(address(sci), addr2, 100e18);
        vm.stopPrank();
    }

    function test_RevertIfLockUsingOtherAddress() public {
        vm.startPrank(addr2);

            bytes4 selector = bytes4(keccak256("Unauthorized(address)"));
            vm.expectRevert(abi.encodeWithSelector(selector, addr2));
            staking.lock(address(don), addr1, 500e18);

            vm.expectRevert(abi.encodeWithSelector(selector, addr2));
            staking.lock(address(sci), addr1, 500e18);
            
        vm.stopPrank();
    }

    function test_FreeSciTokens() public {
        vm.startPrank(addr1);
            staking.lock(address(sci), addr1, 500e18);
        vm.stopPrank();

        vm.roll(block.number + 100);

        vm.startPrank(addr1);
            staking.free(address(sci), addr1, 100e18);
        vm.stopPrank();

        vm.roll(block.number + 200);

        vm.startPrank(addr1);
            staking.free(address(sci), addr1, 100e18);
        vm.stopPrank();

        (
        uint256 stakedPo,
        uint256 stakedSci, 
        uint256 stakedDon, 
        uint256 votingRights, 
        uint256 voteLockTime, 
        uint256 amtSnapshots
        ) = staking.users(addr1);

        assertEq(staking.getTotalStaked(), 300e18);
        assertEq(stakedPo, 0);
        assertEq(stakedSci, 300e18);
        assertEq(stakedDon, 0);
        assertEq(votingRights, 300e18);
        assertEq(voteLockTime, 0);
        assertEq(amtSnapshots, 3);
    }

    function test_FreeDonTokens() public {
        vm.startPrank(addr3);
            staking.lock(address(don), addr3, 500e18);
        vm.stopPrank();

        vm.roll(block.number + 100);

        vm.startPrank(addr3);
            staking.free(address(don), addr3, 100e18);
        vm.stopPrank();

        vm.roll(block.number + 200);

        vm.startPrank(addr3);
            staking.free(address(don), addr3, 100e18);
        vm.stopPrank();

        (
        uint256 stakedPo,
        uint256 stakedSci, 
        uint256 stakedDon, 
        uint256 votingRights, 
        uint256 voteLockTime, 
        uint256 amtSnapshots
        ) = staking.users(addr3);

        assertEq(staking.getTotalStaked(), 300e18);
        assertEq(stakedPo, 0);
        assertEq(stakedSci, 0);
        assertEq(stakedDon, 300e18);
        assertEq(votingRights, 300e18);
        assertEq(voteLockTime, 0);
        assertEq(amtSnapshots, 3);
    }


}