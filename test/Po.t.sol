// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/tokens/Po.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/tokens/Sci.sol";
import "contracts/staking/Staking.sol";

contract PoTest is Test {
    GovernorOperations public gov;
    Po public po;
    MockUsdc public usdc;
    Staking public staking;
    Sci public sci;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address treasuryWallet = vm.addr(6);
    address donationWallet = vm.addr(7);
    address operationsWallet = vm.addr(8);
    bytes32 govIdCircuitId =
        0x729d660e1c02e4e419745e617d643f897a538673ccf1051e093bbfa58b0a120b;
    bytes32 phoneCircuitId =
        0xbce052cf723dca06a21bd3cf838bc518931730fb3db7859fc9cc86f0d5483495;

    function setUp() public {
        usdc = new MockUsdc(10000000e6);

        vm.startPrank(treasuryWallet);
        sci = new Sci(treasuryWallet, 4538400);

        po = new Po("", treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        gov = new GovernorOperations(
            address(addr5),
            address(staking),
            treasuryWallet,
            address(usdc),
            address(sci),
            address(po),
            0x690BF2dB31D39EE0a88fcaC89117b66a588E865a
        );

        gov.setPoToken(address(po));
        staking.setSciToken(address(sci));
        staking.setGovOps(address(gov));
        gov.setGovParams("proposalLifeTime", 8 weeks);
        gov.setGovParams("quorum", 1000e18);
        gov.setGovParams("voteLockTime", 2 weeks);
        po.setGovOps(address(gov));
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
        deal(treasuryWallet, 100000 ether);
        usdc.approve(address(gov), 100000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        deal(address(sci), addr1, 100000000e18);
        deal(addr1, 10000 ether);
        sci.approve(address(gov), 10000e18);
        sci.approve(address(staking), 10000000000000000e18);
        staking.lock(10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        deal(address(sci), addr2, 100000000e18);
        deal(addr2, 10000 ether);
        sci.approve(address(gov), 10000e18);
        sci.approve(address(staking), 10000000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr3);
        deal(address(sci), addr3, 100000000e18);
        deal(addr3, 10000 ether);
        sci.approve(address(gov), 10000e18);
        sci.approve(address(staking), 10000000000000000e18);
        vm.stopPrank();
    }

    function test_ReceivePoTokens() public {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        uint256 id = gov.getProposalIndex();
        gov.propose(
            "Introduction",
            treasuryWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        gov.voteStandard(id, true, 2000e18);
        uint256 balance = po.balanceOf(addr1, 0);
        assertEq(balance, 1);
        assertEq(po.totalSupply(), 1);
        vm.stopPrank();
    }

    function test_BurnPoToken() public {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        uint256 id = gov.getProposalIndex();
        gov.propose(
            "Introduction",
            treasuryWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        gov.voteStandard(id, true, 2000e18);
        uint256 balance = po.balanceOf(addr1, 0);
        assertEq(balance, 1);
        po.burn(addr1, 0, 1);
        uint256 balance1 = po.balanceOf(addr1, 0);
        assertEq(po.totalSupply(), 0);
        assertEq(balance1, 0);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(2000e18);
        gov.voteStandard(id, true, 2000e18);
        vm.stopPrank();
        vm.startPrank(addr3);
        staking.lock(2000e18);
        gov.voteStandard(id, true, 2000e18);
        vm.stopPrank();
        assertEq(po.totalSupply(), 2);
    }
}
