// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Po.sol";
import "contracts/tokens/Sci.sol";
import "contracts/test/Usdc.sol";
import "contracts/staking/Staking.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/executors/AddDelegate.sol";
import "contracts/governance/GovernorExecutor.sol";

contract StakingTest is Test {
    GovernorOperations public govOps;
    GovernorResearch public govRes;
    AddDelegate public addDelegate;
    Po public po;
    Sci public sci;
    Usdc public usdc;
    Staking public staking;
    GovernorExecutor executor;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address researchFundingWallet = vm.addr(6);
    address admin = vm.addr(7);
    address signer = vm.addr(9);
    event Locked(address indexed user, address indexed asset, uint256 amount);
    event Freed(address indexed user, address indexed asset, uint256 amount);

    function setUp() public {
        usdc = new Usdc(10000000e18);

        vm.startPrank(admin);
        sci = new Sci(admin, 18910000);

        po = new Po("", admin);

        staking = new Staking(admin, address(sci));

        govRes = new GovernorResearch(
            address(staking),
            admin,
            researchFundingWallet
        );

        govOps = new GovernorOperations(
            address(staking),
            admin,
            address(po),
            signer
        );

        address[] memory governors = new address[](2);
        governors[0] = address(govOps);
        governors[1] = address(govRes);
        executor = new GovernorExecutor(admin, 2 days, address(govOps), address(govRes));

        staking.setGovOps(address(govOps));
        staking.setGovRes(address(govRes));
        govOps.setPoToken(address(po));
        po.setGovOps(address(govOps));
        govOps.setGovExec(address(executor));
        staking.setGovExec(address(executor));
        vm.stopPrank();

        deal(address(usdc), admin, 10000e18);
        deal(address(usdc), addr1, 10000e18);
        deal(address(usdc), addr2, 10000e18);
        deal(address(usdc), addr3, 10000e18);

        deal(address(sci), addr1, 2000000000e18);
        deal(address(sci), addr2, 1000000e18);
        deal(address(sci), addr3, 1000000e18);
        deal(address(sci), addr4, 1000000e18);
        deal(address(sci), addr5, 1000000e18);
        deal(address(sci), admin, 10000000e18);

        vm.startPrank(addr1);
        sci.approve(address(staking), 2000000000e18);
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
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(govRes), 100000000000000e18);
        sci.approve(address(staking), 100000000000000e18);
        staking.lock(1000e18);
        vm.stopPrank();

        vm.startPrank(admin);
        sci.approve(address(staking), 100000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        staking.lock(2000000e18);
        addDelegate = new AddDelegate(
            addr1,
            address(executor),
            address(staking)
        );
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(addDelegate), false);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();

        vm.startPrank(addr1);
        addDelegate = new AddDelegate(
            addr2,
            address(executor),
            address(staking)
        );
        uint256 id2 = govOps.getProposalIndex();
        govOps.propose("Info", address(addDelegate), false);
        govOps.voteStandard(id2, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id2);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id2);
        assertTrue(staking.getDelegate(addr1) == true);
        assertTrue(staking.getDelegate(addr2) == true);
        vm.stopPrank();
    }

    function test_ReturnUserRights() public {
        assertEq(staking.getLatestUserRights(addr1), 2000000e18);
        assertEq(staking.getUserRights(addr1, 1, block.number), 2000000e18);
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        staking.free(500e18);
        vm.stopPrank();
        assertEq(staking.getLatestUserRights(addr1), (2000000e18 - 500e18));
        assertEq(staking.getUserRights(addr1, 2, block.number), (2000000e18 - 500e18));
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

        assertEq(lockedSci, 2000000e18);
        assertEq(votingRights, 2000000e18);
        assertEq(voteLockEnd, 3343681);
        assertEq(proposeLockEnd, 3343681);
        assertEq(amtSnapshots, 1);
        assertEq(delegate, address(0));

        vm.stopPrank();
    }

    function test_EmitLockEventWithSciTokens() public {
        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);

        emit Locked(addr2, address(sci), 100e18);

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

        assertEq(lockedSci, 2000000e18);
        assertEq(votingRights, 0);
        assertEq(voteLockEnd, 3343681); //4.1 weeks + 3 days + 1 week is lock end!
        assertEq(proposeLockEnd, 3343681);
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
        assertEq(votingRights1, 2000500e18);
        assertEq(amtSnapshots1, 2);
        assertEq(delegate1, address(0));
    }

    function test_FreeTokens() public {
        vm.startPrank(addr1);
        staking.free(1000000e18);
        vm.stopPrank();

        (
            uint256 lockedSci,
            uint256 votingRights,
            ,
            ,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);

        assertEq(lockedSci, 1000000e18);
        assertEq(votingRights, 1000000e18);
        // assertEq(voteLockEnd, 334368);
        // assertEq(proposeLockEnd, 334368);
        assertEq(amtSnapshots, 1);
        assertEq(delegate, address(0));
    }

    function test_FreeTokensIfVotingRightsDelegated() public {
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
        assertEq(lockedSci, (2000000e18 - 300e18));
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
        assertEq(votingRights1, (2000000e18 - 300e18 + 500e18));
        assertEq(amtSnapshots1, 3);
        assertEq(delegate1, address(0));
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
        staking.delegate(addr1);
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
        staking.free(2000000e18);
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
    }

    function test_DelegateVotingRights() public {
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

        assertEq(lockedSci1, 2000000e18);
        assertEq(votingRights1, 0);
        assertEq(voteLockEnd1, 3343681);
        assertEq(proposeLockEnd1, 3343681);
        assertEq(amtSnapshots1, 1);
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
        assertEq(votingRights2, 2000000e18 + 500e18);
        assertEq(voteLockEnd2, 0);
        assertEq(proposeLockEnd2, 0);
        assertEq(amtSnapshots2, 1);
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

        assertEq(lockedSci, 2000000e18);
        assertEq(votingRights, 2000000e18);
        assertEq(voteLockEnd, 3343681);
        assertEq(proposeLockEnd, 3343681);
        assertEq(amtSnapshots, 3);
        assertEq(delegate, address(0));
    }

}
