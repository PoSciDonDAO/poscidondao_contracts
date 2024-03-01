// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/tokens/Participation.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/tokens/Sci.sol";
import "contracts/staking/Staking.sol";

contract ParticipationTest is Test {
    GovernorOperations public gov;
    Participation public po;
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
    bytes32 govIdCircuitId = 0x729d660e1c02e4e419745e617d643f897a538673ccf1051e093bbfa58b0a120b;
    bytes32 phoneCircuitId = 0xbce052cf723dca06a21bd3cf838bc518931730fb3db7859fc9cc86f0d5483495;
    address hubAddress = 0x2AA822e264F8cc31A2b9C22f39e5551241e94DfB;

    function setUp() public {
        usdc = new MockUsdc(10000000e6);

        vm.startPrank(treasuryWallet);
        sci = new Sci(treasuryWallet);

        po = new Participation("", treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        gov = new GovernorOperations(
            address(staking),
            treasuryWallet,
            address(usdc),
            address(sci),
            address(po),
            hubAddress
        );

        po.grantBurnerRole(treasuryWallet);
        gov.setPoToken(address(po));
        staking.setSciToken(address(sci));
        staking.setGovOps(address(gov));
        gov.govParams("proposalLifeTime", 8 weeks);
        gov.govParams("quorum", 1000e18);
        gov.govParams("voteLockTime", 2 weeks);
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
        staking.lockSci(10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        deal(address(sci), addr2, 100000000e18);
        deal(addr2, 10000 ether);
        sci.approve(address(gov), 10000e18);
        sci.approve(address(staking), 10000000000000000e18);
        vm.stopPrank();
    }

    function test_ReceiveParticipationTokens() public {
        vm.startPrank(addr1);
        staking.lockSci(2000e18);
        uint256 id = gov.getOperationsProposalIndex();
        gov.proposeOperation(
            "Introduction",
            treasuryWallet,
            5000000e6,
            0,
            0,
            true,
            false
        );
        gov.voteOnOperations(id, true, 2000e18, phoneCircuitId);
        uint256 balance = po.balanceOf(addr1);
        assertEq(balance, 1);
        vm.stopPrank();
    }

    function test_BurnParticipationTokensWhenTreasuryIsBurner() public {
        vm.startPrank(addr1);
        staking.lockSci(2000e18);
        uint256 id = gov.getOperationsProposalIndex();
        gov.proposeOperation(
            "Introduction",
            treasuryWallet,
            5000000e6,
            0,
            0,
            true,
            false
        );
        gov.voteOnOperations(id, true, 2000e18, phoneCircuitId);
        uint256 balance = po.balanceOf(addr1);
        assertEq(balance, 1);
        vm.stopPrank();

        vm.startPrank(addr2);
        staking.lockSci(2000e18);
        gov.voteOnOperations(id, true, 2000e18, phoneCircuitId);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        po.burn(addr2, 1);
        uint256 balance1 = po.balanceOf(addr2);
        assertEq(balance1, 0);
        vm.stopPrank();
    }
}
