// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Po.sol";
import "contracts/tokens/Sci.sol";
import "contracts/test/Usdc.sol";
import "contracts/sciManager/SciManager.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/governance/GovernorExecutor.sol";
import "contracts/DeployedAddresses.sol";

contract SciManagerTest is Test {
    Usdc usdc;
    Sci sci;
    Po po;
    SciManager sciManager;
    GovernorOperations govOps;
    GovernorResearch govRes;
    GovernorExecutor executor;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address researchFundingWallet = vm.addr(6);
    address admin = DeployedAddresses.admin;
    address signer = vm.addr(9);
    address test = 0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe;

    event Locked(address indexed user, address indexed asset, uint256 amount);
    event Freed(address indexed user, address indexed asset, uint256 amount);

    function setUp() public {
        usdc = Usdc(DeployedAddresses.usdc);

        vm.startPrank(admin);
        sci = Sci(DeployedAddresses.sci);
        po = Po(DeployedAddresses.po);
        // exchange = PoToSciExchange(DeployedAddresses.poToSciExchange);
        sciManager = SciManager(DeployedAddresses.sciManager);
        govOps = GovernorOperations(DeployedAddresses.governorOperations);
        govRes = GovernorResearch(DeployedAddresses.governorResearch);

        address[] memory governors = new address[](2);
        governors[0] = address(govOps);
        governors[1] = address(govRes);

        executor = GovernorExecutor(DeployedAddresses.governorExecutor);

        sci.approve(address(govOps), 100000000000000e18);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(executor), 100000000000000e18);
        usdc.approve(address(executor), 100000000000000e6);
        // sci.approve(address(transaction), 100000000000000e18);
        // usdc.approve(address(transaction), 100000000000000e6);
        sci.approve(address(sciManager), 1000000000000e18);
        deal(address(usdc), admin, 100000000e6);
        deal(address(sci), admin, 10000000e18);

        po.setGovOps(address(govOps));
        sciManager.setGovOps(address(govOps));
        sciManager.setGovRes(address(govRes));
        govOps.setGovExec(address(executor));
        // govOps.setGovGuard(address(guard));
        sciManager.setGovExec(address(executor));
        govRes.setGovExec(address(executor));
        // govRes.setGovGuard(address(guard));
        vm.stopPrank();

        deal(address(usdc), admin, 10000e18);
        deal(address(usdc), test, 10000e18);
        deal(address(usdc), addr1, 10000e18);
        deal(address(usdc), addr2, 10000e18);
        deal(address(usdc), addr3, 10000e18);

        deal(address(sci), test, 2000000000e18);
        deal(address(sci), addr1, 2000000000e18);
        deal(address(sci), addr2, 2000000000e18);
        // deal(address(sci), addr2, 1000000e18);
        deal(address(sci), addr3, 1000000e18);
        deal(address(sci), addr4, 1000000e18);
        deal(address(sci), addr5, 1000000e18);
        deal(address(sci), admin, 10000000e18);

        vm.startPrank(test);
        sci.approve(address(sciManager), 2000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        sci.approve(address(sciManager), 2000000000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        sci.approve(address(sciManager), 2000000000e18);
        vm.stopPrank();

        vm.startPrank(addr3);
        sci.approve(address(sciManager), 10000e18);
        sciManager.lock(500e18);
        vm.stopPrank();

        vm.startPrank(addr4);
        sci.approve(address(sciManager), 10000e18);
        sciManager.lock(500e18);
        vm.stopPrank();

        vm.startPrank(addr5);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(govRes), 100000000000000e18);
        sci.approve(address(sciManager), 100000000000000e18);
        sciManager.lock(1000e18);
        vm.stopPrank();

        vm.startPrank(admin);
        sci.approve(address(sciManager), 100000000000000e18);
        vm.stopPrank();
    }

    function test_ReturnUserRights() public {
        assertEq(sciManager.getLatestUserRights(addr1), 2000000e18);
        assertEq(sciManager.getUserRights(addr1, 1, block.number), 2000000e18);
        vm.roll(block.number + 2);
        vm.startPrank(addr1);
        sciManager.free(500e18);
        vm.stopPrank();
        assertEq(sciManager.getLatestUserRights(addr1), (2000000e18 - 500e18));
        assertEq(
            sciManager.getUserRights(addr1, 2, block.number),
            (2000000e18 - 500e18)
        );
    }

    function test_LockTokens() public {
        vm.startPrank(addr1);
        (
            uint256 lockedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 proposeLockEnd,
            uint256 amtSnapshots
        ) = sciManager.users(addr1);

        assertEq(lockedSci, 2000000e18);
        assertEq(votingRights, 2000000e18);
        assertEq(voteLockEnd, sciManager.getVoteLockEnd(addr1));
        assertEq(proposeLockEnd, sciManager.getProposeLockEnd(addr1));
        assertEq(amtSnapshots, 1);

        vm.stopPrank();
    }

    function test_EmitLockEventWithSciTokens() public {
        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);

        emit Locked(addr2, address(sci), 100e18);

        sciManager.lock(100e18);
        vm.stopPrank();
    }

    function test_FreeTokens() public {
        vm.startPrank(addr1);
        sciManager.free(1000000e18);
        vm.stopPrank();

        (
            uint256 lockedSci,
            uint256 votingRights,
            ,
            ,
            uint256 amtSnapshots
        ) = sciManager.users(addr1);

        assertEq(lockedSci, 1000000e18);
        assertEq(votingRights, 1000000e18);
        // assertEq(voteLockEnd, 334368);
        // assertEq(proposeLockEnd, 334368);
        assertEq(amtSnapshots, 1);
    }
}
