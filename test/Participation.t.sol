// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/tokens/Participation.sol";
import "contracts/test/Token.sol";
import "contracts/tokens/Donation.sol";
import "contracts/tokens/Trading.sol";

contract ParticipationTest is Test {
    
    GovernorResearch public govRes;
    Participation public po;
    Token public usdc;
    Staking public staking;
    Donation public don;
    Trading public sci;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address dao = vm.addr(6);
    address donationWallet = vm.addr(7);
    address treasuryWallet = vm.addr(8);
    address royaltyAddress = vm.addr(9);
    address researchWallet = vm.addr(10);

    function setUp() public {
        usdc = new Token(10000000e18);
        usdc.transfer(addr1, 10000e18);
        usdc.transfer(addr2, 10000e18);
        usdc.transfer(addr3, 1000e18);
        usdc.transfer(addr4, 1000e18);
        usdc.transfer(addr5, 1000e18);
        usdc.transfer(dao, 1000e18);

        vm.startPrank(dao);

            don = new Donation(
                address(usdc),
                donationWallet
            );

            po = new Participation(
                "", 
                dao
            );

            govRes = new GovernorResearch(
                address(staking), 
                treasuryWallet,
                address(usdc),
                address(po)
            );

            staking = new Staking(
                address(po),
                address(sci),
                address(don),
                dao
            );
            staking.setGovRes(address(govRes));

            don.ratioEth(18, 10);
            don.ratioUsdc(10, 10);
            don.setDonationThreshold(1e15);
            don.setStakingContract(address(staking));
            
            govRes.govParams("proposalLifeTime", 8 weeks);
            govRes.govParams("quorum", 1000e18);
            govRes.govParams("voteLockTime", 2 weeks);

            deal(address(usdc), addr1, 10000e18);
            deal(address(usdc), addr2, 10000e18);
            deal(address(usdc), addr3, 10000e18);
            deal(address(usdc), treasuryWallet, 10000000e18);
            deal(treasuryWallet, 100000 ether);

        vm.stopPrank();

        vm.startPrank(addr1);
            usdc.approve(address(don), 1000000000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            usdc.approve(address(don), 1000000000e18);
        vm.stopPrank();
    }

    function test_receiveParticipationTokens() public {
        vm.startPrank(addr1);
            don.donateEth{value: 1 ether}(addr1);
            staking.lock(address(don), addr1, 1000e18);
        vm.stopPrank();        
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();
        vm.startPrank(addr1);

        vm.stopPrank();

    }
}