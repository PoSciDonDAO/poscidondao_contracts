// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/tokens/Po.sol";
import "contracts/test/Usdc.sol";
import "contracts/tokens/Sci.sol";
import "contracts/sciManager/SciManager.sol";

contract PoTest is Test {
    GovernorOperations public govOps;
    Po public po;
    Usdc public usdc;
    SciManager public sciManager;
    Sci public sci;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address admin = vm.addr(6);
    address donationWallet = vm.addr(7);
    address operationsWallet = vm.addr(8);
    address signer = vm.addr(9);

    function setUp() public {
        usdc = new Usdc(10000000e6);

        vm.startPrank(admin);
        sci = new Sci(admin, 4538400);

        po = new Po("", admin);

        sciManager = new SciManager(admin, address(sci));

        govOps = new GovernorOperations(
            address(sciManager),
            admin,
            address(po),
            signer
        );

        govOps.setPoToken(address(po));
        sciManager.setGovOps(address(govOps));
        po.setGovOps(address(govOps));
        vm.stopPrank();

        vm.startPrank(admin);
        deal(admin, 100000 ether);
        usdc.approve(address(govOps), 100000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        deal(address(sci), addr1, 100000000e18);
        deal(addr1, 10000 ether);
        sci.approve(address(govOps), 10000e18);
        sci.approve(address(sciManager), 10000000000000000e18);
        sciManager.lock(10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        deal(address(sci), addr2, 100000000e18);
        deal(addr2, 10000 ether);
        sci.approve(address(govOps), 10000e18);
        sci.approve(address(sciManager), 10000000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr3);
        deal(address(sci), addr3, 100000000e18);
        deal(addr3, 10000 ether);
        sci.approve(address(govOps), 10000e18);
        sci.approve(address(sciManager), 10000000000000000e18);
        vm.stopPrank();
    }

    function test_ReceivePoTokens() public {
        vm.startPrank(addr1);
        sciManager.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(0), false);
        govOps.voteStandard(id, true);
        uint256 balance = po.balanceOf(addr1, 0);
        assertEq(balance, 1);
        assertEq(po.totalSupply(), 1);
        vm.stopPrank();
    }

    function test_BurnPoToken() public {
        vm.startPrank(addr1);
        sciManager.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(0), false);
        govOps.voteStandard(id, true);
        uint256 balance = po.balanceOf(addr1, 0);
        assertEq(balance, 1);
        po.burn(addr1, 0, 1);
        uint256 balance1 = po.balanceOf(addr1, 0);
        assertEq(po.totalSupply(), 0);
        assertEq(balance1, 0);
        vm.stopPrank();
        vm.startPrank(addr2);
        sciManager.lock(2000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(addr3);
        sciManager.lock(2000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        assertEq(po.totalSupply(), 2);
    }

    function test_adminCanMintTokens() public {
        vm.startPrank(admin);
        address[] memory selectedMembers = new address[](1);
        selectedMembers[0] = 0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe;
        po.mintBatchByAdmin(selectedMembers, 5);
        uint256 balance = po.balanceOf(admin, 0);
        assertEq(balance, 5);
        assertEq(po.totalSupply(), 5);
        vm.stopPrank();
    }

    function test_NonAdminCannotMintTokens() public {
        vm.startPrank(addr1);
        vm.expectRevert(
            "AccessControl: account 0x7e5f4552091a69125d5dfcb7b8c2659029395bdf is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        address[] memory selectedMembers = new address[](1);
        selectedMembers[0] = 0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe;
        po.mintBatchByAdmin(selectedMembers, 5);
        vm.stopPrank();
    }

    function test_adminCanTransferTokens() public {
        vm.startPrank(admin);
        address[] memory selectedMembers = new address[](1);
        selectedMembers[0] = admin;
        po.mintBatchByAdmin(selectedMembers, 5);
        po.safeTransferFrom(admin, addr2, 0, 3, "");
        uint256 balance1 = po.balanceOf(admin, 0);
        uint256 balance2 = po.balanceOf(addr2, 0);
        assertEq(balance1, 2);
        assertEq(balance2, 3);
        vm.stopPrank();
    }

    function test_NonadminCannotTransferTokens() public {
        vm.startPrank(admin);
        address[] memory selectedMembers = new address[](1);
        selectedMembers[0] = 0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe;
        po.mintBatchByAdmin(selectedMembers, 5);
        vm.stopPrank();

        vm.startPrank(addr1);
        vm.expectRevert(
            "AccessControl: account 0x7e5f4552091a69125d5dfcb7b8c2659029395bdf is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        po.safeTransferFrom(addr1, addr2, 0, 3, "");
        vm.stopPrank();
    }

    function test_AdminCanBatchTransferTokens() public {
        vm.startPrank(admin);
        address[] memory selectedMembers = new address[](1);
        selectedMembers[0] = admin;
        po.mintBatchByAdmin(selectedMembers, 10);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 0;
        amounts[0] = 6;
        po.safeBatchTransferFrom(admin, addr2, ids, amounts, "");
        uint256 balance1 = po.balanceOf(admin, 0);
        uint256 balance2 = po.balanceOf(addr2, 0);
        assertEq(balance1, 4);
        assertEq(balance2, 6);
        vm.stopPrank();
    }

    function test_NonadminCannotBatchTransferTokens() public {
        vm.startPrank(admin);
        address[] memory selectedMembers = new address[](1);
        selectedMembers[0] = admin;
        po.mintBatchByAdmin(selectedMembers, 10);
        vm.stopPrank();

        vm.startPrank(addr1);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 0;
        amounts[0] = 6;
        vm.expectRevert(
            "AccessControl: account 0x7e5f4552091a69125d5dfcb7b8c2659029395bdf is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        po.safeBatchTransferFrom(addr1, addr2, ids, amounts, "");
        vm.stopPrank();
    }
}
