// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/tokens/Participation.sol";
import "contracts/test/Token.sol";
import "contracts/tokens/Donation.sol";
import "contracts/tokens/Trading.sol";
import "contracts/staking/Staking.sol";

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
            po = new Participation(
                "", 
                dao
            );

            sci = new Trading(
                treasuryWallet
            );

            don = new Donation(
                address(usdc),
                donationWallet
            );

            staking = new Staking(
                address(don),
                dao
            );
                
            govRes = new GovernorResearch(
                address(staking), 
                treasuryWallet,
                address(usdc),
                address(po)
            );

            staking.setPoToken(address(po));
            staking.setSciToken(address(sci));
            staking.setGovRes(address(govRes));
            don.setRatioEth(18, 10);
            don.setRatioUsdc(10, 10);
            don.setDonationThreshold(1e15);
            don.setStakingContract(address(staking));
            po.setStakingContract(address(staking));
            govRes.govParams("proposalLifeTime", 8 weeks);
            govRes.govParams("quorum", 1000e18);
            govRes.govParams("voteLockTime", 2 weeks);
            govRes.setPoPhase(1);

            po.setGovRes(address(govRes));
        vm.stopPrank();

        vm.startPrank(addr1);
            usdc.approve(address(don), 1000000000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            usdc.approve(address(don), 1000000000e18);
        vm.stopPrank();

        deal(address(usdc), addr1, 10000e18);
        deal(address(usdc), addr2, 10000e18);
        deal(address(usdc), addr3, 10000e18);
        deal(address(usdc), treasuryWallet, 10000000e18);
        deal(treasuryWallet, 100000 ether);


        deal(address(sci), addr1, 100000000e18);
        deal(address(don), addr1, 100000000e18);
        deal(addr1, 10000 ether);


        deal(address(sci), addr2, 100000000e18);
        deal(address(don), addr2, 100000000e18);
        deal(addr2, 10000 ether);

        vm.startPrank(addr1);
            sci.approve(address(govRes), 10000e18);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
            usdc.approve(address(govRes), 100000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            sci.approve(address(govRes), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
            sci.approve(address(govRes), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            sci.approve(address(staking), 10000e18);
        vm.stopPrank();
    }

    function test_ReceiveParticipationTokens() public {
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();
        vm.startPrank(addr1);
            don.donateEth{value: 1 ether}(addr1);
            staking.lock(address(don), addr1, 1000e18);
            uint256 id = govRes.getProposalIndex();
            govRes.vote(id, addr1, GovernorResearch.Vote.Yes, 1000e18);
            uint256[] memory balance = po.getHeldBalance(addr1);
            assertEq(balance[0], 0);   
        vm.stopPrank();
        vm.startPrank(addr2);
            don.donateEth{value: 1 ether}(addr2);
            staking.lock(address(don), addr2, 1000e18);
            uint256 id2 = govRes.getProposalIndex();
            govRes.vote(id2, addr2, GovernorResearch.Vote.Yes, 1000e18);
            uint256[] memory balance2 = po.getHeldBalance(addr2);
            assertEq(balance2[0], 1);   
        vm.stopPrank();
    }

    function test_StakeParticipationTokens() public {
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();
        vm.startPrank(addr1);
            don.donateEth{value: 1 ether}(addr1);
            staking.lock(address(don), addr1, 1000e18);
            uint256 id = govRes.getProposalIndex();
            govRes.vote(id, addr1, GovernorResearch.Vote.Yes, 1000e18);
        vm.stopPrank();

        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();

        vm.startPrank(addr1);
            don.donateEth{value: 1 ether}(addr1);
            staking.lock(address(don), addr1, 1000e18);
            uint256 id2 = govRes.getProposalIndex();
            govRes.vote(id2, addr1, GovernorResearch.Vote.Yes, 1000e18);

            staking.lock(address(po), addr1, po.getHeldBalance(addr1).length);
            (uint256 stakedPo,,,,,) = staking.users(addr1);
            uint256[] memory balanceHeld = po.getHeldBalance(addr1);
            uint256[] memory balanceStaked = po.getStakedBalance(addr1);
            assertEq(balanceHeld.length, 0);
            assertEq(stakedPo, 2);
            assertEq(balanceStaked.length, 2);
         vm.stopPrank();
    }

    function test_UnstakeParticipationTokens() public {
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();

        vm.startPrank(addr1);
            don.donateEth{value: 1 ether}(addr1);
            staking.lock(address(don), addr1, 1000e18);
            uint256 id = govRes.getProposalIndex();
            govRes.vote(id, addr1, GovernorResearch.Vote.Yes, 1000e18);

            staking.lock(address(po), addr1, po.getHeldBalance(addr1).length);
            staking.free(address(po), addr1, po.getStakedBalance(addr1).length);

            uint256[] memory balanceStaked = po.getStakedBalance(addr1);
            uint256[] memory balanceHeld = po.getHeldBalance(addr1);
            assertEq(balanceStaked.length, 0);
            assertEq(balanceHeld.length, 1);

        vm.stopPrank();
    }

    function propose() public {
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();
    }

    function donateAndLock() public {
        vm.startPrank(addr1);
            don.donateEth{value: 1 ether}(addr1);
            staking.lock(address(don), addr1, 1000e18);
        vm.stopPrank();
    }

    function vote() public {
        vm.startPrank(addr1);
            uint256 id = govRes.getProposalIndex();
            govRes.vote(id, addr1, GovernorResearch.Vote.Yes, 1000e18);
        vm.stopPrank();
    }

    function test_StakeMultipleParticipationTokens() public {
        donateAndLock();
        for(uint256 i = 0; i < 5; i++) {
            propose();
            vote();
        }

        vm.startPrank(addr1);
            uint256[] memory balanceStaked = po.getStakedBalance(addr1);
            uint256[] memory balanceHeld = po.getHeldBalance(addr1);
            assertEq(balanceStaked.length, 0);
            assertEq(balanceHeld.length, 5);
            staking.lock(address(po), addr1, 5);
            (uint256 stakedPo,,,,,) = staking.users(addr1);
            assertEq(stakedPo, 5);
            uint256[] memory balanceStaked2 = po.getStakedBalance(addr1);
            uint256[] memory balanceHeld2 = po.getHeldBalance(addr1);
            assertEq(balanceStaked2.length, 5);
            assertEq(balanceHeld2.length, 0);
        vm.stopPrank();
    }
}