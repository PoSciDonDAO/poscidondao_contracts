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
    address royaltyAddress = vm.addr(8);

    function setUp() public {
        usdc = new MockUsdc(10000000e6);

        vm.startPrank(treasuryWallet);
            sci = new Sci(
                treasuryWallet
            );

            staking = new Staking(
                treasuryWallet,
                address(sci)
            );

            po = new Participation(
                "", 
                treasuryWallet,
                address(staking)
            );
                
            gov = new GovernorOperations(
                address(staking), 
                treasuryWallet,
                donationWallet,
                address(usdc),
                address(sci)
            );

            gov.setPoToken(address(po));
            staking.setPoToken(address(po));
            staking.setSciToken(address(sci));
            staking.setGovOps(address(gov));
            po.setStaking(address(staking));
            gov.govParams("proposalLifeTime", 8 weeks);
            gov.govParams("quorum", 1000e18);
            gov.govParams("voteLockTime", 2 weeks);
            gov.setPoPhase(1);
            po.setGov(address(gov));
        vm.stopPrank();

        deal(address(usdc), addr1, 10000e18);
        deal(address(usdc), addr2, 10000e18);
        deal(address(usdc), addr3, 10000e18);
        deal(address(usdc), treasuryWallet, 10000000e18);
        deal(treasuryWallet, 100000 ether);


        deal(address(sci), addr1, 100000000e18);
        deal(addr1, 10000 ether);


        deal(address(sci), addr2, 100000000e18);
        deal(addr2, 10000 ether);

        vm.startPrank(addr1);
            sci.approve(address(gov), 10000e18);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
            usdc.approve(address(gov), 100000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            sci.approve(address(gov), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
            sci.approve(address(gov), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            sci.approve(address(staking), 10000000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
            sci.approve(address(staking), 10000000000000000e18);
            staking.lock(address(sci), addr1, 10000e18);
        vm.stopPrank();
    }

    function test_ReceiveParticipationTokens() public {
        vm.startPrank(addr1);
            staking.lock(address(sci), addr1, 1000e18);
            gov.proposeOperation("Introduction", treasuryWallet, 5000000e6, 0, 0, true);        
            uint256 id = gov.getOperationsProposalIndex();
            gov.voteOnOperations(id, addr1, true, 1000e18); 
            uint256 balance = po.balanceOf(addr1); 
            assertEq(balance, 1);
        vm.stopPrank();
    }

    function test_StakeParticipationTokens() public {
        vm.startPrank(addr1);
            staking.lock(address(sci), addr1, 1000e18);
            gov.proposeOperation("Introduction", treasuryWallet, 5000000e6, 0, 0, true);
            uint256 id = gov.getOperationsProposalIndex();
        vm.stopPrank();

        vm.startPrank(addr2);
            staking.lock(address(sci), addr2, 1000e18);
            gov.voteOnOperations(id, addr2, true, 1000e18);
            staking.lock(address(po), addr2, po.balanceOf(addr2));
            assertEq(staking.getStakedPo(addr2), 1);
         vm.stopPrank();
    }

    function test_UnstakeParticipationTokens() public {
        vm.startPrank(addr1);
            staking.lock(address(sci), addr1, 1000e18);
            gov.proposeOperation("Introduction", treasuryWallet, 5000000e6, 0, 0, true);
            uint256 id = gov.getOperationsProposalIndex();
            gov.voteOnOperations(id, addr1, true, 1000e18);
            
            assertEq(po.balanceOf(addr1), 1);
            assertEq(staking.getStakedPo(addr1), 0);
            
            staking.lock(address(po), addr1, po.balanceOf(addr1));
            
            assertEq(po.balanceOf(addr1), 0);
            assertEq(staking.getStakedPo(addr1), 1);
            
            staking.free(address(po), addr1, staking.getStakedPo(addr1));
            
            assertEq(po.balanceOf(addr1), 1);
            assertEq(staking.getStakedPo(addr1), 0);
        vm.stopPrank();
    }

    function test_StakeMultipleParticipationTokens() public {
        vm.startPrank(addr1);
            staking.lock(address(sci), addr1, 1000e18);
            gov.proposeOperation("Introduction", treasuryWallet, 5000000e6, 0, 0, true);
        vm.stopPrank();
        vm.startPrank(addr2);
            uint256 id = gov.getOperationsProposalIndex();
            staking.lock(address(sci), addr2, 1000e18);
            gov.voteOnOperations(id, addr2, true, 1000e18);
        vm.stopPrank();
        vm.startPrank(addr1);
            staking.lock(address(sci), addr1, 1000e18);
            gov.proposeOperation("Introduction2", treasuryWallet, 5000000e6, 0, 0, true);
        vm.stopPrank();
        vm.startPrank(addr2);
            uint256 id2 = gov.getOperationsProposalIndex();
            staking.lock(address(sci), addr2, 1000e18);
            gov.voteOnOperations(id2, addr2, true, 1000e18);
            assertEq(po.balanceOf(addr2), 2);
            staking.lock(address(po), addr2, po.balanceOf(addr2));
            assertEq(staking.getStakedPo(addr2), 2);
         vm.stopPrank();

    }

    // function test_StakeMultipleParticipationTokens() public {
    //     lock();
    //     for(uint256 i = 0; i < 5; i++) {
    //         proposeOperation();
    //         vote();
    //     }

    //     vm.startPrank(addr1);
    //         uint256[] memory balanceStaked = po.getStakedBalance(addr1);
    //         uint256[] memory balanceHeld = po.getHeldBalance(addr1);
    //         assertEq(balanceStaked.length, 0);
    //         assertEq(balanceHeld.length, 5);
    //         staking.lock(address(po), addr1, 5);
    //         (uint256 stakedPo,,,,) = staking.users(addr1);
    //         assertEq(stakedPo, 5);
    //         uint256[] memory balanceStaked2 = po.getStakedBalance(addr1);
    //         uint256[] memory balanceHeld2 = po.getHeldBalance(addr1);
    //         assertEq(balanceStaked2.length, 5);
    //         assertEq(balanceHeld2.length, 0);
    //     vm.stopPrank();
    // }
}