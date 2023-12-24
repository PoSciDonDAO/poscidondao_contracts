// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/SCI.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/staking/Staking.sol";
import "contracts/governance/Governor.sol";

contract StakingTest is Test {
    Governor public gov;
    Participation public po;
    SCI public sci;
    MockUsdc public usdc;
    Staking public staking;

    address public addr1 = vm.addr(1);
    address public addr2 = vm.addr(2);
    address public addr3 = vm.addr(3);
    address public addr4 = vm.addr(4);
    address public addr5 = vm.addr(5);
    address public donationWallet = vm.addr(6);
    address public treasuryWallet = vm.addr(7);

    event Locked(address indexed token, address indexed user, uint256 amount);
    event Freed(address indexed token, address indexed user, uint256 amount);

    function setUp() public {
        usdc = new MockUsdc(10000000e18);

        vm.startPrank(treasuryWallet);
        sci = new SCI(treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        po = new Participation("", treasuryWallet, address(staking));

        gov = new Governor(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        staking.setPoToken(address(po));
        staking.setSciToken(address(sci));
        staking.setGov(address(gov));
        gov.setPoPhase(1);
        gov.setPoToken(address(po));
        gov.govParams("proposalLifeTime", 4 weeks);
        gov.govParams("quorum", 1000e18);
        gov.govParams("voteLockTime", 2 weeks);
        po.setGov(address(gov));
        vm.stopPrank();

        deal(address(usdc), treasuryWallet, 10000e18);
        deal(address(usdc), addr1, 10000e18);
        deal(address(usdc), addr2, 10000e18);
        deal(address(usdc), addr3, 10000e18);

        deal(address(sci), addr1, 100000000e18);

        deal(address(sci), addr2, 100000000e18);

        deal(address(sci), addr3, 100000000e18);

        vm.startPrank(addr1);
        sci.approve(address(staking), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        sci.approve(address(staking), 10000e18);
        vm.stopPrank();
    }

    function test_LockSciTokens() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 500e18);

        (
            uint256 stakedPo,
            uint256 stakedSci,
            uint256 votingRights,
            uint256 voteLockTime,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(stakedPo, 0);
        assertEq(stakedSci, sci.balanceOf(address(staking)));
        assertEq(votingRights, 500e18);
        assertEq(voteLockTime, 0);
        assertEq(amtSnapshots, 1);
        assertEq(delegate, address(0));

        vm.stopPrank();
    }

    function test_EmitLockEventWithSciTokens() public {
        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);

        emit Locked(address(sci), addr2, 100e18);

        staking.lock(address(sci), addr2, 100e18);
        vm.stopPrank();
    }

    function test_RevertIfLockUsingOtherAddress() public {
        vm.startPrank(addr2);

        bytes4 selector = bytes4(keccak256("Unauthorized(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, addr2));
        staking.lock(address(sci), addr1, 500e18);

        vm.expectRevert(abi.encodeWithSelector(selector, addr2));
        staking.lock(address(treasuryWallet), addr1, 500e18);

        vm.stopPrank();
    }

    function test_LockPoTokens() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 1000e18);
        gov.proposeOperation(
            "Introduction",
            treasuryWallet,
            5000000e6,
            0,
            0,
            true
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 200e18);
        uint256 id = gov.getOperationsProposalIndex();
        gov.voteOnOperations(id, addr2, true, 150e18); //can we vote on our own proposal?
        staking.lock(address(po), addr2, 1);
        assertEq(staking.getStakedPo(addr2), 1);
        vm.stopPrank();
    }

    function test_FreePoTokens() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 1000e18);
        gov.proposeOperation(
            "Introduction",
            treasuryWallet,
            5000000e6,
            0,
            0,
            true
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 200e18);
        uint256 id = gov.getOperationsProposalIndex();
        gov.voteOnOperations(id, addr2, true, 150e18); //can we vote on our own proposal?
        staking.lock(address(po), addr2, 1);
        staking.free(address(po), addr2, 1);
        assertEq(staking.getStakedPo(addr2), 0);
        assertEq(po.balanceOf(addr2), 1);
        vm.stopPrank();
    }

    function test_FreeSciTokens() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 500e18);
        vm.stopPrank();

        vm.roll(block.number + 1);

        vm.startPrank(addr1);
        staking.free(address(sci), addr1, 100e18);
        vm.stopPrank();

        vm.roll(block.number + 2);

        vm.startPrank(addr1);
        staking.free(address(sci), addr1, 100e18);
        vm.stopPrank();

        (
            uint256 stakedPo,
            uint256 stakedSci,
            uint256 votingRights,
            uint256 voteLockTime,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(staking.getTotalStaked(), 300e18);
        assertEq(stakedPo, 0);
        assertEq(stakedSci, 300e18);
        assertEq(votingRights, 300e18);
        assertEq(voteLockTime, 0);
        assertEq(amtSnapshots, 3);
        assertEq(delegate, address(0));
    }

    function test_DelegateVotingRights() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 500e18);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(addr1, addr2);
        (
            uint256 stakedPo1,
            uint256 stakedSci1,
            uint256 votingRights1,
            uint256 voteLockTime1,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr1);
        vm.stopPrank();

        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(stakedPo1, 0);
        assertEq(stakedSci1, 500e18);
        assertEq(votingRights1, 0);
        assertEq(voteLockTime1, 0);
        assertEq(amtSnapshots1, 2); //1?
        assertEq(delegate1, addr2);

        (
            uint256 stakedPo2,
            uint256 stakedSci2,
            uint256 votingRights2,
            uint256 voteLockTime2,
            uint256 amtSnapshots2,
            address delegate2
        ) = staking.users(addr2);

        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(stakedPo2, 0);
        assertEq(stakedSci2, 0);
        assertEq(votingRights2, 500e18);
        assertEq(voteLockTime2, 0);
        assertEq(amtSnapshots2, 1);
        assertEq(delegate2, address(0));
    }
}
