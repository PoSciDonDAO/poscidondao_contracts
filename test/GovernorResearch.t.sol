// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/Donation.sol";
import "contracts/tokens/Trading.sol";
import "contracts/tokens/ImpactNft.sol";
import "contracts/test/Token.sol";
import "contracts/staking/Staking.sol";

contract GovernorResearchTest is Test {

    GovernorResearch public govRes;
    Participation public po;
    Trading public sci;
    Donation public don;
    ImpactNft public nft;
    Token public usdc;
    Staking public staking;

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

    event Locked(address indexed user, address indexed gov, uint256 deposit, uint256 votes);
    event Freed(address indexed gov, address indexed user, uint256 amount, uint256 remainingVotes);

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
                dao, 
                royaltyAddress
            );

            sci = new Trading(
                treasuryWallet
            );

            don = new Donation(
                address(usdc),
                donationWallet
            );

            staking = new Staking(
                address(po),
                address(sci),
                address(don),
                dao
            );
                
            govRes = new GovernorResearch(
                address(staking), 
                treasuryWallet,
                address(usdc),
                address(po)
            );

            staking.setGovRes(address(govRes));

            don.ratioEth(18, 10);
            don.ratioUsdc(10,10);
            don.setDonationThreshold(1e15);
            don.setStakingContract(address(staking));
            
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
        deal(address(don), addr1, 100000000e18);
        deal(addr1, 10000 ether);


        deal(address(sci), addr2, 100000000e18);
        deal(address(don), addr2, 100000000e18);
        deal(addr2, 10000 ether);

        vm.startPrank(addr1);
            sci.approve(address(govRes), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            sci.approve(address(govRes), 10000e18);
        vm.stopPrank();
    }

    function test_AddingAndRemovingGov() public {
        vm.startPrank(dao);
            govRes.addGov(addr1);
            assertEq(govRes.wards(addr1), 1);

            govRes.removeGov(addr1);
            assertEq(govRes.wards(addr1), 0);
        vm.stopPrank();
    }

    function test_SetGovParams() public {
        assertEq(govRes.proposalLifeTime(), 8 weeks);
        assertEq(govRes.quorum(), 1000e18);
        assertEq(govRes.voteLockTime(), 2 weeks);
    }

    function test_SetParticipationToken() public {
        vm.startPrank(dao);
            address addressPo = address(govRes.poToken());
            govRes.setPoAddress(addressPo);
            assertEq(addressPo, govRes.po());
        vm.stopPrank();
    }

    function test_Proposal() public {
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
            (uint256 startBlockNum, 
            uint256 endTimeStamp, 
            GovernorResearch.ProposalStatus status, 
            uint256 votesFor,
            uint256 votesAgainst, 
            uint256 totalVotes
            ) = govRes.getProposalInfo(govRes.getProposalIndex());

            assertEq(startBlockNum, block.number);
            assertEq(endTimeStamp, block.timestamp + govRes.proposalLifeTime());
            assertTrue(status == GovernorResearch.ProposalStatus.Active);
            assertEq(votesFor, 0);
            assertEq(votesAgainst, 0);
            assertEq(totalVotes, 0);

            (
                string memory info,
                address wallet,
                uint256 amountUsdc,
                uint256 amountEth
            ) = govRes.getProposalProjectInfo(govRes.getProposalIndex());

            assertEq(info, "Introduction");
            assertEq(wallet, researchWallet);
            assertEq(amountUsdc, 5000000e18);
            assertEq(amountEth, 0);
        vm.stopPrank();
    }

    function test_VoteFor() public {
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();

        vm.startPrank(addr1);
            don.donateUsdc(addr1, 200e18);
            staking.lock(address(don), addr1, 200e18);
            assertEq(address(govRes), staking.govRes());
            govRes.vote(govRes.getProposalIndex(), addr1, GovernorResearch.Vote.Yes, 100e18);

            (,,, 
            uint256 votesFor,
            uint256 votesAgainst,   
            uint256 totalVotes
            ) = govRes.getProposalInfo(govRes.getProposalIndex());

            assertEq(votesFor, 100e18);
            assertEq(votesAgainst, 0);
            assertEq(totalVotes, 100e18);

            (
            ,,,,
            uint256 voteLockTime, 
            ) = staking.users(addr1);

            assertEq(voteLockTime, (block.timestamp + govRes.voteLockTime()));
        vm.stopPrank();
    }

    function test_RevertVoteIfUserNotMsgSender() public {
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();

        vm.startPrank(addr2);
            don.donateEth{value: 100 ether}(addr2);
            staking.lock(address(don), addr2, 180000e18);
        vm.stopPrank();

        vm.startPrank(addr3);
            bytes4 selector = bytes4(keccak256("Unauthorized(address)"));
            vm.expectRevert(abi.encodeWithSelector(selector, addr3));
            govRes.vote(1, addr2, GovernorResearch.Vote.Yes, 100000e18);
        vm.stopPrank();
    }

    function test_RevertVoteWithVoteLockIfAlreadyVoted() public {
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();

        vm.startPrank(addr2);
            don.donateEth{value: 100 ether}(addr2);
            staking.lock(address(don), addr2, 180000e18);

            uint256 id = govRes.getProposalIndex();
            govRes.vote(id, addr2, GovernorResearch.Vote.Yes, 100000e18);
            bytes4 selector = bytes4(keccak256("VoteLock()"));
            vm.expectRevert(selector);
            govRes.vote(id, addr2, GovernorResearch.Vote.Yes, 1800e18);
        vm.stopPrank();
    }

    function test_RevertVoteWithInsufficientRights() public {
        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();
        vm.startPrank(addr2);
            don.donateEth{value: 100 ether}(addr2);
            staking.lock(address(don), addr2, 180e18);

            bytes4 selector = bytes4(keccak256("InsufficientVotingRights(uint256,uint256)"));
            vm.expectRevert(abi.encodeWithSelector(selector, 180e18, 1.8e23));
            govRes.vote(1, addr2, GovernorResearch.Vote.Yes, 1.8e23);
        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {

        vm.startPrank(dao);
            govRes.propose("Introduction", researchWallet, 5000000e18, 0);
        vm.stopPrank();
        vm.startPrank(addr1);
            don.donateEth{value: 100 ether}(addr2);
            staking.lock(address(don), addr1, 1.8e23);
        vm.stopPrank();
        vm.startPrank(addr1);
            bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
            vm.expectRevert(selector);
            govRes.vote(2, addr1, GovernorResearch.Vote.Yes, 1.8e28);
        vm.stopPrank();
    }

    // function test_RevertVoteIfVotingIsFinalized() public {
    //     don.donateEth{value: 1000 ether}(addr2);
    //     govRes.lock(address(don), addr2, 1.6e24);
    //     vm.startPrank(dao);
    //         govRes.propose("Introduction", researchWallet, 5000000e18, 0);
    //     vm.stopPrank();
    //     uint256 id = govRes.getProposalIndex();
    //     govRes.vote(id, addr2, GovernorResearch.Vote.Yes, 1.2e24);
    //     vm.startPrank(dao);
    //         govRes.finalizeVoting(id);
    //         (,,GovernorResearch.ProposalStatus status,,,,,,, 
    //         ) = govRes.proposals(id);
    //         assertTrue(status == GovernorResearch.ProposalStatus.scheduled);
    //     vm.stopPrank();
    //     (,,,,uint256 amtSnapshots2) = govRes.users(addr2);
    //     bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
    //     vm.expectRevert(abi.encodeWithSelector(selector, 1));
    //     govRes.vote(id, addr2, amtSnapshots2, "REO", 0.4e23);
    // }

    // function test_RevertFreeTokensWhenVotesLocked() public {
    //     vm.startPrank(dao);
    //         govRes.propose("NDV", "ADV", "REO");
    //     vm.stopPrank();
    //     don.donateEth{value: 1 ether}(addr2); // receive 1600 tokens
    //     govRes.lock(address(don), addr2, 1600e18); //receive 20% more voting power --> 1920 vp
    //     (,,,,uint256 amtSnapshots) = govRes.users(addr2);
    //     govRes.vote(govRes.getProposalIndex(), addr2, amtSnapshots, "REO", 1920e18);
    //     (,,, uint256 voteLockTime,) = govRes.users(addr2);
    //     bytes4 selector = bytes4(keccak256("TokensStillLocked(uint256,uint256)"));
    //     vm.expectRevert(abi.encodeWithSelector(selector, voteLockTime, block.timestamp));
    //     govRes.free(address(don), addr2, 1520e18);
    // }

    // function test_FreeTokensAterVotingAndAfterVoteLockTimePassed() public {
    //     vm.startPrank(dao);
    //         govRes.propose("NDV", "ADV", "REO");
    //     vm.stopPrank();
    //     don.donateEth{value: 1 ether}(addr2); // receive 1600 tokens
    //     govRes.lock(address(don), addr2, 1600e18); //receive 20% more voting power --> 1920 vp
    //     (,,,,uint256 amtSnapshots) = govRes.users(addr2);
    //     govRes.vote(1, addr2, amtSnapshots, "REO", 1700e18);
    //     (,,,uint256 voteLockTime, 
    //     ) = govRes.users(addr2);
    //     vm.warp(voteLockTime);
    //     govRes.free(address(don), addr2, 1520e18); 
    // }

    // function test_FinalizeVoting() public {
    //     vm.startPrank(dao);
    //         govRes.propose("NDV", "ADV", "REO");
    //     vm.stopPrank();
    //     govRes.lock(address(sci), addr2, 2000e18);
    //     (,,,,uint256 amtSnapshots) = govRes.users(addr2);
    //     uint256 id = govRes.getProposalIndex();
    //     govRes.vote(id, addr2, amtSnapshots, "REO", 2000e18);
    //     vm.startPrank(dao);
    //         govRes.finalizeVoting(id);
    //     vm.stopPrank();
    //     (,,GovernorResearch.ProposalStatus status,,,,,,, 
    //     ) = govRes.proposals(id);
    //     assertTrue(status == GovernorResearch.ProposalStatus.scheduled);
    // }

    // function test_RevertFinalizeVotingWithQuorumNotReached() public {
    //     vm.startPrank(dao);
    //         govRes.propose("NDV", "ADV", "REO");
    //     vm.stopPrank();
    //     govRes.lock(address(sci), addr2, 2000e18);
    //     (,,,,uint256 amtSnapshots) = govRes.users(addr2);
    //     uint256 id = govRes.getProposalIndex();
    //     govRes.vote(id, addr2, amtSnapshots, "REO", 100e18);
    //     vm.startPrank(dao);
    //         bytes4 selector = bytes4(keccak256("QuorumNotReached()"));
    //         vm.expectRevert(selector);
    //         govRes.finalizeVoting(id);
    //     vm.stopPrank();
    // }

    // function test_ExecuteProposal() public {
    //     vm.startPrank(dao);
    //         govRes.propose("NDV", "ADV", "REO");
    //     vm.stopPrank();
    //     govRes.lock(address(sci), addr2, 2000e18);
    //     (,,,,uint256 amtSnapshots) = govRes.users(addr2);
    //     uint256 id = govRes.getProposalIndex();
    //     govRes.vote(id, addr2, amtSnapshots, "REO", 2000e18);
    //     vm.startPrank(dao);
    //         govRes.finalizeVoting(id);
    //         govRes.executeProposal(id);
    //         (,,GovernorResearch.ProposalStatus status,,,,,,, 
    //         ) = govRes.proposals(govRes.getProposalIndex());
    //         assertTrue(status == GovernorResearch.ProposalStatus.executed);
    //     vm.stopPrank();
    // }

    // function test_CancelProposal() public {
    //     vm.startPrank(dao);
    //         govRes.propose("NDV", "ADV", "REO");
    //     vm.stopPrank();
    //     govRes.lock(address(sci), addr2, 2000e18);
    //     (,,,,uint256 amtSnapshots) = govRes.users(addr2);
    //     uint256 id = govRes.getProposalIndex();
    //     govRes.vote(id, addr2, amtSnapshots, "REO", 2000e18);
    //     vm.startPrank(dao);
    //         govRes.cancelProposal(id);
    //         (,,GovernorResearch.ProposalStatus status,,,,,,, 
    //         ) = govRes.proposals(govRes.getProposalIndex());
    //         assertTrue(status == GovernorResearch.ProposalStatus.cancelled);
    //     vm.stopPrank();
    // }

    // function test_RevertProposalExecutionFunctionIfIncorrectPhase() public {
    //     vm.startPrank(dao);
    //         govRes.propose("NDV", "ADV", "REO");
    //     vm.stopPrank();
    //     govRes.lock(address(sci), addr2, 2000e18);
    //     (,,,,uint256 amtSnapshots) = govRes.users(addr2);
    //     uint256 id = govRes.getProposalIndex();
    //     govRes.vote(id, addr2, amtSnapshots, "REO", 2000e18);
    //     vm.startPrank(dao);
    //         bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
    //         vm.expectRevert(abi.encodeWithSelector(selector, GovernorResearch.ProposalStatus.active));
    //         govRes.executeProposal(id);
    //     vm.stopPrank();
    // }
}