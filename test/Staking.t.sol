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
    address hubAddress = 0x2AA822e264F8cc31A2b9C22f39e5551241e94DfB;

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
            address(po),
            hubAddress
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
        deal(address(sci), addr4, 100000000e18);
        deal(address(sci), addr5, 100000000e18);

        vm.startPrank(addr1);
        sci.approve(address(staking), 10000e18);
        staking.lock(500e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        sci.approve(address(staking), 10000e18);
        staking.lock(500e18);
        vm.stopPrank();

        vm.startPrank(addr3);
        sci.approve(address(staking), 10000e18);
        staking.lock(500e18);
        vm.stopPrank();

        vm.startPrank(addr4);
        sci.approve(address(staking), 10000e18);
        staking.lock(500e18);
        vm.stopPrank();

        vm.startPrank(addr5);
        sci.approve(address(staking), 10000e18);
        staking.lock(500e18);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
        staking.addDelegate(addr2);
        staking.addDelegate(addr3);
        vm.stopPrank();
    }
    function test_ReturnUserRights() public {
        assertEq(staking.getLatestUserRights(addr1), 500e18);
        assertEq(staking.getUserRights(addr1, 1, block.number), 500e18);
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.free(500e18);
        vm.stopPrank();
        assertEq(staking.getLatestUserRights(addr1), 0);
        assertEq(staking.getUserRights(addr1, 2, block.number), 0);
    }

    function test_lockTokens() public {
        vm.startPrank(addr1);
        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(lockedSci, 500e18);
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

        staking.lock(100e18);
        vm.stopPrank();
    }

    function test_lockTokensIfVotingRightsDelegated() public {
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(addr2);
        vm.stopPrank();
        vm.roll(block.number + 2);
        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(lockedSci, 500e18);
        assertEq(votingRights, 0);
        assertEq(voteLockEnd, 0);
        assertEq(proposeLockEnd, 0);
        assertEq(amtSnapshots, 2);
        assertEq(delegate, addr2);

        (
            uint256 lockedSci1,
            uint256 votingRights1,
            ,
            ,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr2);
        assertEq(lockedSci1, 500e18);
        assertEq(votingRights1, 1000e18);
        assertEq(amtSnapshots1, 2);
        assertEq(delegate1, address(0));
    }

    function test_freeTokens() public {
        vm.roll(block.number + 1);

        vm.startPrank(addr1);
        staking.free(100e18);
        vm.stopPrank();

        vm.roll(block.number + 2);

        vm.startPrank(addr1);
        staking.free(100e18);
        vm.stopPrank();

        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(lockedSci, 300e18);
        assertEq(votingRights, 300e18);
        assertEq(voteLockEnd, 0);
        assertEq(proposeLockEnd, 0);
        assertEq(amtSnapshots, 3);
        assertEq(delegate, address(0));
    }

    function test_freeTokensIfVotingRightsDelegated() public {
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(addr2);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.free(300e18);
        vm.stopPrank();
        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);
        assertEq(lockedSci, 200e18);
        assertEq(votingRights, 0);
        assertEq(voteLockEnd, 0);
        assertEq(proposeLockEnd, 0);
        assertEq(amtSnapshots, 2);
        assertEq(delegate, addr2);

        (
            uint256 lockedSci1,
            uint256 votingRights1,
            ,
            ,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr2);
        assertEq(lockedSci1, 500e18);
        assertEq(votingRights1, 700e18);
        assertEq(amtSnapshots1, 3);
        assertEq(delegate1, address(0)); //Cannot further delegate tokens
    }

    function test_RevertDelegationIfOldAndNewDelegatesSimilar() public {
        vm.startPrank(addr1);
        staking.delegate(addr2);
        bytes4 selector = bytes4(keccak256("AlreadyDelegated()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        staking.delegate(addr2);
    }

    function test_RevertSelfDelegationNotAllowed() public {
        vm.startPrank(addr2);
        staking.lock(500e18); // Ensure addr1 has some locked SCI for delegation
        bytes4 selector = bytes4(keccak256("SelfDelegationNotAllowed()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        staking.delegate(addr2); // Attempt to self-delegate
    }

    function test_RevertDelegationToAlreadyDelegatedUser() public {
        vm.startPrank(addr2);
        staking.delegate(addr3);
        vm.stopPrank();

        vm.startPrank(addr1);
        bytes4 selector = bytes4(
            keccak256("CannotDelegateToAnotherDelegator()")
        );
        vm.expectRevert(abi.encodeWithSelector(selector));
        staking.delegate(addr2);
        vm.stopPrank();
    }

    function test_RevertDelegationWithoutVotingPower() public {
        vm.startPrank(addr1);
        staking.free(500e18);
        bytes4 selector = bytes4(keccak256("NoVotingPowerToDelegate()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        staking.delegate(addr2);
        vm.stopPrank();
    }

    function test_RevertDelegationIfDelegateNotAllowListed() public {
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("DelegateNotAllowListed(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, addr5));
        staking.delegate(addr5);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
        staking.addDelegate(addr4);
        vm.stopPrank();

        vm.startPrank(addr2);
        staking.delegate(addr4);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
        staking.removeDelegate(addr4);
        vm.stopPrank();

        vm.startPrank(addr1);
        vm.expectRevert(abi.encodeWithSelector(selector, addr4));
        staking.delegate(addr4);
        vm.stopPrank();
    }

    function test_DelegateVotingRights() public {
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(addr2);
        (
            uint256 lockedSci1,
            uint256 votingRights1,
            uint256 voteLockEnd1,
            uint256 proposeLockEnd1,
            uint256 amtSnapshots1,
            address delegate1
        ) = staking.users(addr1);
        vm.stopPrank();

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

        assertEq(lockedSci2, 500e18);
        assertEq(votingRights2, 1000e18);
        assertEq(voteLockEnd2, 0);
        assertEq(proposeLockEnd2, 0);
        assertEq(amtSnapshots2, 2);
        assertEq(delegate2, address(0));
    }

    function test_RemoveDelegateIfDelegated() public {
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(addr2);
        vm.stopPrank();
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.delegate(address(0));
        vm.stopPrank();
        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(lockedSci, 500e18);
        assertEq(votingRights, 500e18);
        assertEq(voteLockEnd, 0);
        assertEq(proposeLockEnd, 0);
        assertEq(amtSnapshots, 3);
        assertEq(delegate, address(0));
    }
}
