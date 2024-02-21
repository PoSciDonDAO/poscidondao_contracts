// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/tokens/Participation.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/tokens/Sci.sol";
import "contracts/staking/Staking.sol";
import "contracts/exchange/PoToSciExchange.sol";

contract PoToSciExchangeTest is Test {
    GovernorOperations public gov;
    Participation public po;
    MockUsdc public usdc;
    Staking public staking;
    Sci public sci;
    PoToSciExchange public ex;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address treasuryWallet = vm.addr(6);
    address donationWallet = vm.addr(7);
    address operationsWallet = vm.addr(8);
    address rewardWallet = vm.addr(9);
    string info = "Info";

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
            address(po)
        );

        ex = new PoToSciExchange(rewardWallet, address(sci), address(po));
        po.grantBurnerRole(address(ex));

        gov.setPoToken(address(po));
        staking.setSciToken(address(sci));
        staking.setGovOps(address(gov));
        gov.govParams("proposalLifeTime", 8 weeks);
        gov.govParams("quorum", 1000e18);
        gov.govParams("voteLockTime", 2 weeks);
        po.setGovOps(address(gov));
        vm.stopPrank();

        vm.startPrank(rewardWallet);
        deal(rewardWallet, 100000 ether);
        deal(address(sci), rewardWallet, 100000000e18);
        usdc.approve(address(gov), 100000000000000e18);
        sci.approve(address(ex), 10000000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        deal(address(sci), addr1, 100000000e18);
        deal(addr1, 10000 ether);
        sci.approve(address(gov), 10000e18);
        sci.approve(address(staking), 10000000000000000e18);
        staking.lockSci(10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        deal(address(sci), addr2, 500e18);
        deal(addr2, 10000 ether);
        sci.approve(address(gov), 10000e18);
        sci.approve(address(staking), 10000000000000000e18);
        vm.stopPrank();
    }

    function test_SetConversionRate() public {
        vm.startPrank(rewardWallet);
        ex.setConversionRate(5);
        assertEq(ex.conversionRate(), 5);
        vm.stopPrank();
    }

    function test_ExchangePoForSci() public {
        vm.startPrank(addr1);
        staking.lockSci(500e18);
        uint256 id = gov.getOperationsProposalIndex();
        gov.proposeOperation(
            info,
            operationsWallet,
            50000e6,
            0,
            0,
            true,
            false
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lockSci(500e18);
        gov.voteOnOperations(id, true, 500e18);
        assertEq(po.balanceOf(addr2), 1);
        ex.exchangePoForSci(addr2, 1);
        assertEq(po.balanceOf(addr2), 0);
        assertEq(sci.balanceOf(addr2), 1.8e18);
        vm.stopPrank();
    }
}
