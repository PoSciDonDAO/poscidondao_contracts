// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/Sci.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/staking/Staking.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/governance/GovernorResearch.sol";

contract StakingTest is Test {
    GovernorOperations public govOps;
    GovernorResearch public govRes;
    Participation public po;
    Sci public sci;
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
        sci = new Sci(treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        po = new Participation("", treasuryWallet, address(staking));

        govOps = new GovernorOperations(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        govRes = new GovernorResearch(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        staking.setPoToken(address(po));
        staking.setSciToken(address(sci));
        staking.setGovOps(address(govOps));
        staking.setGovRes(address(govRes));
        govOps.setPoPhase(1);
        govOps.setPoToken(address(po));
        govOps.govParams("proposalLifeTime", 4 weeks);
        govOps.govParams("quorum", 1000e18);
        govOps.govParams("voteLockEnd", 2 weeks);
        po.setGov(address(govOps));
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
            uint256 voteLockEnd,
            uint256 proposalLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(stakedPo, 0);
        assertEq(stakedSci, sci.balanceOf(address(staking)));
        assertEq(votingRights, 500e18);
        assertEq(voteLockEnd, 0);
        assertEq(proposalLockEnd, 0);
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
        vm.stopPrank();
    }

    function test_RevertIfWrongToken() public {
        vm.startPrank(addr2);

        bytes4 selector = bytes4(keccak256("WrongToken()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        staking.lock(address(treasuryWallet), addr2, 500e18);
    }

    function test_LockPoTokens() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 1000e18);
        govOps.proposeOperation("Info", treasuryWallet, 500e6, 0, 0, true, false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 200e18);
        uint256 id = govOps.getOperationsProposalIndex();
        govOps.voteOnOperations(id, addr2, true, 150e18);
        staking.lock(address(po), addr2, 1);
        assertEq(staking.getStakedPo(addr2), 1);
        vm.stopPrank();
    }

    function test_FreePoTokens() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 1000e18);
        govOps.proposeOperation("Info", treasuryWallet, 500e6, 0, 0, true, false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 200e18);
        uint256 id = govOps.getOperationsProposalIndex();
        govOps.voteOnOperations(id, addr2, true, 150e18);
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
            uint256 voteLockEnd,
            uint256 proposalLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(staking.getTotalStaked(), 300e18);
        assertEq(stakedPo, 0);
        assertEq(stakedSci, 300e18);
        assertEq(votingRights, 300e18);
        assertEq(voteLockEnd, 0);
        assertEq(proposalLockEnd, 0);
        assertEq(amtSnapshots, 3);
        assertEq(delegate, address(0));
    }

    function test_DelegateVotingRightsIfOwner() public {
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
            uint256 voteLockEnd1,
            uint256 proposalLockEnd1,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr1);
        vm.stopPrank();

        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(stakedPo1, 0);
        assertEq(stakedSci1, 500e18);
        assertEq(votingRights1, 0);
        assertEq(voteLockEnd1, 0);
        assertEq(proposalLockEnd1, 0);
        assertEq(amtSnapshots1, 2);
        assertEq(delegate1, addr2);

        (
            uint256 stakedPo2,
            uint256 stakedSci2,
            uint256 votingRights2,
            uint256 voteLockEnd2,
            uint256 proposalLockEnd2,
            uint256 amtSnapshots2,
            address delegate2
        ) = staking.users(addr2);

        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(stakedPo2, 0);
        assertEq(stakedSci2, 0);
        assertEq(votingRights2, 500e18);
        assertEq(voteLockEnd2, 0);
        assertEq(proposalLockEnd2, 0);
        assertEq(amtSnapshots2, 1);
        assertEq(delegate2, address(0));
    }

    function test_RemoveDelegateIfDelegated() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 500e18);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(addr1, addr2);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr2);
        staking.delegate(addr1, address(0));
        vm.stopPrank();
        (
            uint256 stakedPo,
            uint256 stakedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposalLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);
        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(stakedPo, 0);
        assertEq(stakedSci, 500e18);
        assertEq(votingRights, 500e18);
        assertEq(voteLockEnd, 0);
        assertEq(proposalLockEnd, 0);
        assertEq(amtSnapshots, 3);
        assertEq(delegate, address(0));
    }

    function test_LockSciTokensIfVotingRightsDelegated() public {
        vm.startPrank(addr1);
        staking.delegate(addr1, addr2); //gives 0 voting rights
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 500e18); //delegates 500 voting rights after locking
        vm.stopPrank();
        (
            uint256 stakedPo,
            uint256 stakedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposalLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);
        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(stakedPo, 0);
        assertEq(stakedSci, 500e18);
        assertEq(votingRights, 0);
        assertEq(voteLockEnd, 0);
        assertEq(proposalLockEnd, 0);
        assertEq(amtSnapshots, 1);
        assertEq(delegate, addr2);

        (
            ,
            uint256 stakedSci1,
            uint256 votingRights1,
            ,
            ,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr2);
        assertEq(stakedSci1, 0);
        assertEq(votingRights1, 500e18);
        assertEq(amtSnapshots1, 2);
        assertEq(delegate1, address(0));
    }

    function test_FreeSciTokensIfVotingRightsDelegated() public {
        vm.startPrank(addr1);
        staking.delegate(addr1, addr2); //gives 0 voting rights
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 500e18); //delegates 500 voting rights after locking
        vm.stopPrank();
        // vm.roll(block.number + 2);
        // vm.warp(1 days);
        vm.startPrank(addr1);
        staking.free(address(sci), addr1, 300e18); //delegates 500 voting rights after locking
        vm.stopPrank();
        (
            uint256 stakedPo,
            uint256 stakedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposalLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);
        assertEq(staking.getTotalStaked(), 200e18);
        assertEq(stakedPo, 0);
        assertEq(stakedSci, 200e18);
        assertEq(votingRights, 0);
        assertEq(voteLockEnd, 0);
        assertEq(proposalLockEnd, 0);
        assertEq(amtSnapshots, 1);
        assertEq(delegate, addr2);

        (
            ,
            uint256 stakedSci1,
            uint256 votingRights1,
            ,
            ,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr2);
        assertEq(stakedSci1, 0);
        assertEq(votingRights1, 200e18);
        assertEq(amtSnapshots1, 2);
        assertEq(delegate1, address(0));
    }

    function test_RevertDelegationIfMsgSenderNotOwnerOrOldDelegate() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 500e18);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        (, , , , , , address delegate) = staking.users(addr1);
        bytes4 selector = bytes4(
            keccak256("UnauthorizedDelegation(address,address,address)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(selector, addr3, delegate, addr2)
        );
        staking.delegate(addr3, addr2);
    }

    function test_RevertDelegationIfOldAndNewDelegatesSimilar() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 500e18);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(addr1, addr2);
        bytes4 selector = bytes4(keccak256("AlreadyDelegated()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        staking.delegate(addr1, addr2);
    }
}
