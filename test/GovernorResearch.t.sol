// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/Donation.sol";
import "contracts/tokens/Trading.sol";
import "contracts/tokens/GovernorNft.sol";
import "contracts/test/Token.sol";

contract GovernorResearchTest is Test {

    GovernorResearch public govRes;
    Participation public po;
    Trading public sci;
    Donation public don;
    GovernorNft public nft;
    Token public usdc;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address admin = vm.addr(6);
    address donationWallet = vm.addr(7);
    address treasuryWallet = vm.addr(8);

    event Locked(address indexed user, address indexed gov, uint256 deposit, uint256 votes);
    event Freed(address indexed gov, address indexed user, uint256 amount, uint256 remainingVotes);

    function setUp() public {

        usdc = new Token(10000000e18);
        usdc.transfer(addr1, 10000e18);
        usdc.transfer(addr2, 10000e18);
        usdc.transfer(addr3, 1000e18);
        usdc.transfer(addr4, 1000e18);
        usdc.transfer(addr5, 1000e18);
        usdc.transfer(admin, 1000e18);

        vm.startPrank(admin);
            sci = new Trading(
                donationWallet,
                treasuryWallet
            );

            don = new Donation(
                address(usdc),
                donationWallet
            );
            don.ratioEth(16, 10);
            don.ratioUsdc(10,10);
            don.setTreshold(1e15);
                
            govRes = new GovernorResearch(
                address(sci), address(don)
            );

            don.setGovRes(address(govRes));
            
            govRes.govParams("proposalLifeTime", 8 weeks);
            govRes.govParams("quorum", 1000e18);
            govRes.govParams("voteLockTime", 2 weeks);
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

        deal(address(sci), addr1, 100000000e18);
        deal(address(sci), addr2, 100000000e18);

        vm.startPrank(addr1);
            sci.approve(address(govRes), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            sci.approve(address(govRes), 10000e18);
        vm.stopPrank();
    }

    function test_AddingAndRemovingGov() public {
        vm.startPrank(admin);
            govRes.addGov(addr1);
            assertEq(govRes.govs(addr1), 1);

            govRes.removeGov(addr1);
            assertEq(govRes.govs(addr1), 0);
        vm.stopPrank();
    }

    function test_GovParams() public {
        assertEq(govRes.proposalLifeTime(), 8 weeks);
        assertEq(govRes.quorum(), 1000e18);
        assertEq(govRes.voteLockTime(), 2 weeks);
    }

    function test_SetParticipationToken() public {
        vm.startPrank(admin);
            address poAddress = vm.addr(12);
            govRes.setPoToken(poAddress);
            assertEq(govRes.getPoToken(), poAddress);
            assertEq(address(govRes.poToken()), poAddress);
        vm.stopPrank();
    }

    function test_LockWithDonTokens() public {
        don.donateUsdc(addr1, 100e18);
        govRes.lock(address(don), addr1, 100e18);

        (uint256 depositsSci, 
        uint256 depositsDon, 
        uint256 rights, 
        uint256 voteLockTime, 
        uint256 amtSnapshots) = govRes.users(addr1);

        assertEq(depositsSci, 0);
        assertEq(depositsDon, don.balanceOf(address(govRes)));
        assertEq(rights, (100e18*12/10));
        assertEq(voteLockTime, 0);
        assertEq(amtSnapshots, 1);
    }

    function test_EmitLockEventWithDonTokens() public {
        don.donateUsdc(addr1, 100e18);
        vm.expectEmit(true, true, true, true);

        emit Locked(address(don), addr1, 100e18, (100e18*12/10));

        govRes.lock(address(don), addr1, 100e18);
    }

    function test_LockWithSciTokens() public {
        govRes.lock(address(sci), addr1, 200e18);

        (uint256 depositsSci, 
        uint256 depositsDon, 
        uint256 rights, 
        uint256 voteLockTime, 
        uint256 amtSnapshots
        ) = govRes.users(addr1);

        assertEq(depositsSci, 200e18);
        assertEq(depositsDon, 0);
        assertEq(rights, 200e18);
        assertEq(voteLockTime, 0);
        assertEq(amtSnapshots, 1);
    }

    function test_EmitLockEventWithSciTokens() public {
        vm.expectEmit(true, true, true, true);

        emit Locked(address(sci), addr1, 150e18, 150e18);

        govRes.lock(address(sci), addr1, 150e18);
    }

    function test_Proposal() public {
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
            (uint256 startBlockNum, 
            uint256 endTimeStamp, 
            GovernorResearch.ProposalStatus status, 
            bytes32 option1, 
            bytes32 option2, 
            bytes32 option3, 
            uint256 votesOpt1,
            uint256 votesOpt2,
            uint256 votesOpt3,   
            uint256 totalVotes
            ) = govRes.proposals(govRes.getProposalIndex());

            assertEq(startBlockNum, block.number);
            assertEq(endTimeStamp, block.timestamp + govRes.proposalLifeTime());
            assertTrue(status == GovernorResearch.ProposalStatus.active);
            assertEq(option1, "NDV");
            assertEq(option2, "ADV");
            assertEq(option3, "REO");
            assertEq(votesOpt1, 0);
            assertEq(votesOpt2, 0);
            assertEq(votesOpt3, 0);
            assertEq(totalVotes, 0);
        vm.stopPrank();
    }

    function test_Voting() public {
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();

        govRes.lock(address(sci), addr1, 100e18);
        (,,,,uint256 amtSnapshots) = govRes.users(addr1);
        govRes.vote(govRes.getProposalIndex(), addr1, amtSnapshots, "NDV", 100e18);

        (,,,,,, 
        uint256 votesOpt1,
        uint256 votesOpt2,
        uint256 votesOpt3,   
        uint256 totalVotes
        ) = govRes.proposals(govRes.getProposalIndex());

        assertEq(votesOpt1, 100e18);
        assertEq(votesOpt2, 0);
        assertEq(votesOpt3, 0);
        assertEq(totalVotes, 100e18);

        don.donateEth{value: 1 ether}(addr2);
        govRes.lock(address(don), addr2, 1600e18);
        (,,,,uint256 amtSnapshots2) = govRes.users(addr2);
        govRes.vote(govRes.getProposalIndex(), addr2, amtSnapshots2, "REO", 1600e18);

        (,,,,,, 
        uint256 votesOpt12,
        uint256 votesOpt22,
        uint256 votesOpt32,   
        uint256 totalVotes2
        ) = govRes.proposals(govRes.getProposalIndex());

        assertEq(votesOpt12, 100e18);
        assertEq(votesOpt22, 0);
        assertEq(votesOpt32, 1600e18);
        assertEq(totalVotes2, 1700e18);
    }

    function test_RevertVoteWithVoteLockIfAlreadyVoted() public {
        don.donateEth{value: 100 ether}(addr2);
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        govRes.lock(address(don), addr2, 1.6e23);
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        uint256 id = govRes.getProposalIndex();
        govRes.vote(id, addr2, amtSnapshots, "REO", 160000e18);
        bytes4 selector = bytes4(keccak256("VoteLock()"));
        vm.expectRevert(selector);
        govRes.vote(id, addr2, amtSnapshots, "REO", 1600e18);
    }

    function test_RevertVoteWithInsufficientRights() public {
        don.donateEth{value: 100 ether}(addr2);
        govRes.lock(address(don), addr2, 160e18);
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        bytes4 selector = bytes4(keccak256("InsufficientRights(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 192e18, 1.6e23));
        govRes.vote(1, addr2, amtSnapshots, "REO", 1.6e23);
    }

    function test_RevertVoteIfProposalInexistent() public {
        don.donateEth{value: 100 ether}(addr2);
        govRes.lock(address(don), addr2, 1.6e23);
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        govRes.vote(2, addr2, amtSnapshots, "REO", 1.6e28);
    }

    function test_RevertVoteIfVotingIsFinalized() public {
        don.donateEth{value: 1000 ether}(addr2);
        govRes.lock(address(don), addr2, 1.6e24);
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        uint256 id = govRes.getProposalIndex();
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        govRes.vote(id, addr2, amtSnapshots, "REO", 1.2e24);
        vm.startPrank(admin);
            govRes.finalizeVoting(id);
            (,,GovernorResearch.ProposalStatus status,,,,,,, 
            ) = govRes.proposals(id);
            assertTrue(status == GovernorResearch.ProposalStatus.scheduled);
        vm.stopPrank();
        (,,,,uint256 amtSnapshots2) = govRes.users(addr2);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1));
        govRes.vote(id, addr2, amtSnapshots2, "REO", 0.4e23);
    }

    function test_FreeTokens() public {
        don.donateEth{value: 1 ether}(addr2); // receive 1600 tokens
        govRes.lock(address(don), addr2, 1600e18); //receive 20% more voting power --> 1920 vp
        govRes.free(address(don), addr2, 1520e18); //96 vp left
        
        (uint256 depositsSci, 
        uint256 depositsDon, 
        uint256 rights, 
        uint256 voteLockTime, 
        uint256 amtSnapshots) = govRes.users(addr2);

        assertEq(depositsSci, 0);
        assertEq(depositsDon, 80e18);
        assertEq(rights, 96e18);
        assertEq(voteLockTime, 0);
        assertEq(amtSnapshots, 1);
    }

    function test_EmitFreeEventWithSciTokens() public {
        govRes.lock(address(sci), addr2, 100e18);
        vm.expectEmit(true, true, true, true);

        emit Freed(address(sci), addr2, 80e18, 20e18);

        govRes.free(address(sci), addr2, 80e18);
    }

    function test_EmitFreeEventWithDonTokens() public {
        don.donateUsdc(addr2, 100e18);
        govRes.lock(address(don), addr2, 100e18);
        vm.expectEmit(true, true, true, true);

        emit Freed(address(don), addr2, 80e18, 20e18*12/10);

        govRes.free(address(don), addr2, 80e18);
    }

    function test_RevertFreeTokensWhenVotesLocked() public {
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        don.donateEth{value: 1 ether}(addr2); // receive 1600 tokens
        govRes.lock(address(don), addr2, 1600e18); //receive 20% more voting power --> 1920 vp
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        govRes.vote(govRes.getProposalIndex(), addr2, amtSnapshots, "REO", 1920e18);
        (,,, uint256 voteLockTime,) = govRes.users(addr2);
        bytes4 selector = bytes4(keccak256("TokensStillLocked(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, voteLockTime, block.timestamp));
        govRes.free(address(don), addr2, 1520e18);
    }

    function test_FreeTokensAterVotingAndAfterVoteLockTimePassed() public {
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        don.donateEth{value: 1 ether}(addr2); // receive 1600 tokens
        govRes.lock(address(don), addr2, 1600e18); //receive 20% more voting power --> 1920 vp
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        govRes.vote(1, addr2, amtSnapshots, "REO", 1700e18);
        (,,,uint256 voteLockTime, 
        ) = govRes.users(addr2);
        vm.warp(voteLockTime);
        govRes.free(address(don), addr2, 1520e18); 
    }

    function test_FinalizeVoting() public {
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        govRes.lock(address(sci), addr2, 2000e18);
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        uint256 id = govRes.getProposalIndex();
        govRes.vote(id, addr2, amtSnapshots, "REO", 2000e18);
        vm.startPrank(admin);
            govRes.finalizeVoting(id);
        vm.stopPrank();
        (,,GovernorResearch.ProposalStatus status,,,,,,, 
        ) = govRes.proposals(id);
        assertTrue(status == GovernorResearch.ProposalStatus.scheduled);
    }

    function test_RevertFinalizeVotingWithQuorumNotReached() public {
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        govRes.lock(address(sci), addr2, 2000e18);
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        uint256 id = govRes.getProposalIndex();
        govRes.vote(id, addr2, amtSnapshots, "REO", 100e18);
        vm.startPrank(admin);
            bytes4 selector = bytes4(keccak256("QuorumNotReached()"));
            vm.expectRevert(selector);
            govRes.finalizeVoting(id);
        vm.stopPrank();
    }

    function test_ExecuteProposal() public {
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        govRes.lock(address(sci), addr2, 2000e18);
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        uint256 id = govRes.getProposalIndex();
        govRes.vote(id, addr2, amtSnapshots, "REO", 2000e18);
        vm.startPrank(admin);
            govRes.finalizeVoting(id);
            govRes.executeProposal(id);
            (,,GovernorResearch.ProposalStatus status,,,,,,, 
            ) = govRes.proposals(govRes.getProposalIndex());
            assertTrue(status == GovernorResearch.ProposalStatus.executed);
        vm.stopPrank();
    }

    function test_CancelProposal() public {
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        govRes.lock(address(sci), addr2, 2000e18);
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        uint256 id = govRes.getProposalIndex();
        govRes.vote(id, addr2, amtSnapshots, "REO", 2000e18);
        vm.startPrank(admin);
            govRes.cancelProposal(id);
            (,,GovernorResearch.ProposalStatus status,,,,,,, 
            ) = govRes.proposals(govRes.getProposalIndex());
            assertTrue(status == GovernorResearch.ProposalStatus.cancelled);
        vm.stopPrank();
    }

    function test_RevertProposalExecutionFunctionIfIncorrectPhase() public {
        vm.startPrank(admin);
            govRes.propose("NDV", "ADV", "REO");
        vm.stopPrank();
        govRes.lock(address(sci), addr2, 2000e18);
        (,,,,uint256 amtSnapshots) = govRes.users(addr2);
        uint256 id = govRes.getProposalIndex();
        govRes.vote(id, addr2, amtSnapshots, "REO", 2000e18);
        vm.startPrank(admin);
            bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
            vm.expectRevert(abi.encodeWithSelector(selector, GovernorResearch.ProposalStatus.active));
            govRes.executeProposal(id);
        vm.stopPrank();
    }
}