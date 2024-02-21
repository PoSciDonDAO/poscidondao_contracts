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

        po = new Participation("", treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        govOps = new GovernorOperations(
            address(staking),
            treasuryWallet,
            address(usdc),
            address(sci),
            address(po)
        );

        govRes = new GovernorResearch(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        staking.setGovOps(address(govOps));
        staking.setGovRes(address(govRes));
        govOps.setPoToken(address(po));
        govOps.govParams("proposalLifeTime", 4 weeks);
        govOps.govParams("quorum", 1000e18);
        govOps.govParams("voteLockEnd", 2 weeks);
        po.setGovOps(address(govOps));
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
        staking.lockSci(500e18);

        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(lockedSci, sci.balanceOf(address(staking)));
        assertEq(votingRights, 500e18);
        assertEq(voteLockEnd, 0);
        assertEq(proposeLockEnd, 0);
        assertEq(amtSnapshots, 1);
        assertEq(delegate, address(0));

        vm.stopPrank();
    }

    function test_EmitLockEventWithSciTokens() public {
        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);

        emit Locked(address(sci), addr2, 100e18);

        staking.lockSci(100e18);
        vm.stopPrank();
    }

    function test_FreeSciTokens() public {
        vm.startPrank(addr1);
        staking.lockSci(500e18);
        vm.stopPrank();

        vm.roll(block.number + 1);

        vm.startPrank(addr1);
        staking.freeSci(100e18);
        vm.stopPrank();

        vm.roll(block.number + 2);

        vm.startPrank(addr1);
        staking.freeSci(100e18);
        vm.stopPrank();

        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(staking.getTotalStaked(), 300e18);
        assertEq(lockedSci, 300e18);
        assertEq(votingRights, 300e18);
        assertEq(voteLockEnd, 0);
        assertEq(proposeLockEnd, 0);
        assertEq(amtSnapshots, 3);
        assertEq(delegate, address(0));
    }

    function test_ReturnUserRights() public {
        assertEq(staking.getLatestUserRights(addr1), 0);
        assertEq(staking.getUserRights(addr1, 0, block.number), 0);
        vm.startPrank(addr1);
        staking.lockSci(100e18);
        vm.stopPrank();
        assertEq(staking.getLatestUserRights(addr1), 100e18);
        assertEq(staking.getUserRights(addr1, 1, block.number), 100e18);
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.freeSci(100e18);
        vm.stopPrank();
        assertEq(staking.getLatestUserRights(addr1), 0);
        assertEq(staking.getUserRights(addr1, 2, block.number), 0);
    }

    function test_DelegateVotingRightsIfOwner() public {
        vm.startPrank(addr1);
        staking.lockSci(500e18);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(addr1, addr2);
        (
            uint256 lockedSci1,
            uint256 votingRights1,
            uint256 voteLockEnd1,
            uint256 proposeLockEnd1,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr1);
        vm.stopPrank();

        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(lockedSci1, 500e18);
        assertEq(votingRights1, 0);
        assertEq(voteLockEnd1, 0);
        assertEq(proposeLockEnd1, 0);
        assertEq(amtSnapshots1, 2);
        assertEq(delegate1, addr2);

        (
            uint256 lockedSci2,
            uint256 votingRights2,
            uint256 voteLockEnd2,
            uint256 proposeLockEnd2,
            uint256 amtSnapshots2,
            address delegate2
        ) = staking.users(addr2);

        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(lockedSci2, 0);
        assertEq(votingRights2, 500e18);
        assertEq(voteLockEnd2, 0);
        assertEq(proposeLockEnd2, 0);
        assertEq(amtSnapshots2, 1);
        assertEq(delegate2, address(0));
    }

    function test_RemoveDelegateIfDelegated() public {
        vm.startPrank(addr1);
        staking.lockSci(500e18);
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
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);
        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(lockedSci, 500e18);
        assertEq(votingRights, 500e18);
        assertEq(voteLockEnd, 0);
        assertEq(proposeLockEnd, 0);
        assertEq(amtSnapshots, 3);
        assertEq(delegate, address(0));
    }

    function test_LockSciTokensIfVotingRightsDelegated() public {
        vm.startPrank(addr1);
        staking.delegate(addr1, addr2); //gives 0 voting rights
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.lockSci(500e18); //delegates 500 voting rights after locking
        vm.stopPrank();
        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);
        assertEq(staking.getTotalStaked(), 500e18);
        assertEq(lockedSci, 500e18);
        assertEq(votingRights, 0);
        assertEq(voteLockEnd, 0);
        assertEq(proposeLockEnd, 0);
        assertEq(amtSnapshots, 1);
        assertEq(delegate, addr2);

        (
            uint256 lockedSci1,
            uint256 votingRights1,
            ,
            ,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr2);
        assertEq(lockedSci1, 0);
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
        staking.lockSci(500e18); //delegates 500 voting rights after locking
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.freeSci(300e18); //delegates 500 voting rights after locking
        vm.stopPrank();
        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);
        assertEq(staking.getTotalStaked(), 200e18);
        assertEq(lockedSci, 200e18);
        assertEq(votingRights, 0);
        assertEq(voteLockEnd, 0);
        assertEq(proposeLockEnd, 0);
        assertEq(amtSnapshots, 1);
        assertEq(delegate, addr2);

        (
            uint256 lockedSci1,
            uint256 votingRights1,
            ,
            ,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr2);
        assertEq(lockedSci1, 0);
        assertEq(votingRights1, 200e18);
        assertEq(amtSnapshots1, 2);
        assertEq(delegate1, address(0));
    }

    function test_RevertDelegationIfMsgSenderNotOwnerOrOldDelegate() public {
        vm.startPrank(addr1);
        staking.lockSci(500e18);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        (, , , , , address delegate) = staking.users(addr1);
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
        staking.lockSci(500e18);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(addr1, addr2);
        bytes4 selector = bytes4(keccak256("AlreadyDelegated()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        staking.delegate(addr1, addr2);
    }
}
