// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/Sci.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/staking/Staking.sol";

contract GovernorResearchTest is Test {
    GovernorResearch public gov;
    Participation public po;
    Sci public sci;
    MockUsdc public usdc;
    Staking public staking;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address donationWallet = vm.addr(6);
    address treasuryWallet = vm.addr(7);
    address researchWallet = vm.addr(8);

    event Locked(
        address indexed user,
        address indexed gov,
        uint256 deposit,
        uint256 votes
    );
    event Freed(
        address indexed gov,
        address indexed user,
        uint256 amount,
        uint256 remainingVotes
    );

    function setUp() public {
        usdc = new MockUsdc(10000000e18);

        vm.startPrank(treasuryWallet);
        sci = new Sci(treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        po = new Participation("", treasuryWallet, address(staking));

        staking.setPoToken(address(po));
        staking.setSciToken(address(sci));

        gov = new GovernorResearch(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        staking.setGovRes(address(gov));

        gov.govParams("proposalLifeTime", 4 weeks);
        gov.govParams("quorum", 1);
        gov.govParams("voteLockTime", 2 weeks);
        vm.stopPrank();

        deal(address(sci), addr1, 10000000000e18);
        deal(address(usdc), addr1, 10000e6);
        deal(addr1, 10000 ether);

        deal(address(sci), addr2, 10000000000e18);
        deal(address(usdc), addr2, 10000e6);
        deal(addr2, 10000 ether);

        deal(address(sci), treasuryWallet, 10000000000e18);
        deal(address(usdc), treasuryWallet, 100000000e6);
        deal(treasuryWallet, 10000 ether);

        deal(address(sci), donationWallet, 10000000000e18);
        deal(address(usdc), donationWallet, 10000000e6);
        deal(donationWallet, 5000 ether);

        vm.startPrank(treasuryWallet);
        usdc.approve(address(gov), 100000000000000e6);
        sci.approve(address(gov), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();

        vm.startPrank(donationWallet);
        usdc.approve(address(gov), 100000000000000e6);
        sci.approve(address(gov), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        sci.approve(address(gov), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        sci.approve(address(gov), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();
    }

    function test_SetGovParams() public {
        assertEq(gov.proposalLifeTime(), 4 weeks);
        assertEq(gov.quorum(), 1);
        assertEq(gov.voteLockTime(), 2 weeks);
    }

    function test_OperationsProposalUsingUsdc() public {
        vm.startPrank(treasuryWallet);
        staking.lock(address(sci), treasuryWallet, 200e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0,
            true
        );

        (
            uint256 startBlockNum,
            uint256 endTimeStamp,
            GovernorResearch.ProposalStatus status,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 totalVotes
        ) = gov.getResearchProposalInfo(gov.getResearchProposalIndex());

        assertEq(startBlockNum, block.number);
        assertEq(endTimeStamp, block.timestamp + gov.proposalLifeTime());
        assertTrue(status == GovernorResearch.ProposalStatus.Active);
        assertEq(votesFor, 0);
        assertEq(votesAgainst, 0);
        assertEq(totalVotes, 0);

        (string memory info, address wallet, , uint256 amount) = gov
            .getResearchProposalProjectInfo(gov.getResearchProposalIndex());

        assertEq(info, "Introduction");
        assertEq(wallet, researchWallet);
        assertEq(amount, 5000000e6);
        vm.stopPrank();
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 200e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0,
            true
        );
        gov.voteOnResearch(
            gov.getResearchProposalIndex(),
            addr1,
            true,
            100e18
        );

        (, , , uint256 votesFor, uint256 votesAgainst, uint256 totalVotes) = gov
            .getResearchProposalInfo(gov.getResearchProposalIndex());

        assertEq(votesFor, 100e18);
        assertEq(votesAgainst, 0);
        assertEq(totalVotes, 100e18);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + gov.voteLockTime()));
        vm.stopPrank();
    }

    function test_RevertVoteIfUserNotMsgSender() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 180e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0,
            true
        );
        vm.stopPrank();

        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 180000e18);
        vm.stopPrank();

        vm.startPrank(addr3);
        uint256 id = gov.getResearchProposalIndex();
        bytes4 selector = bytes4(keccak256("Unauthorized(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, addr3));
        gov.voteOnResearch(id, addr2, true, 100000e18);
        vm.stopPrank();
    }

    function test_RevertVoteWithVoteLockIfAlreadyVoted() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 10000e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0,
            true
        );
        uint256 id = gov.getResearchProposalIndex();
        gov.voteOnResearch(id, addr2, true, 10000e18);
        bytes4 selector = bytes4(keccak256("VoteLock()"));
        vm.expectRevert(selector);
        gov.voteOnResearch(id, addr2, true, 1800e18);
        vm.stopPrank();
    }

    function test_RevertVoteWithInsufficientRights() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 180e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0
        );
        bytes4 selector = bytes4(
            keccak256("InsufficientVotingRights(uint256,uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, 180e18, 1.8e23));
        gov.voteOnResearch(1, addr2, true, 1.8e23);
        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 1.8e23);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0
        );
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        gov.voteOnResearch(2, addr1, true, 1.8e28);
        vm.stopPrank();
    }

    function test_RevertIfQuorumNotReached() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 180e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0
        );
        uint256 id = gov.getResearchProposalIndex();
        vm.warp(4.1 weeks);
        bytes4 selector = bytes4(keccak256("QuorumNotReached()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        gov.finalizeVotingResearchProposal(id);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 180e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0
        );
        uint256 id = gov.getResearchProposalIndex();
        uint256 proposalLifeTime = gov.proposalLifeTime();
        bytes4 selector = bytes4(keccak256("ProposalOngoing(uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, 1, proposalLifeTime + 1)
        );
        gov.finalizeVotingResearchProposal(id);
        vm.stopPrank();
    }

    function test_finalizeVotingResearchProposal() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 120e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0
        );
        vm.stopPrank();
        uint256 id = gov.getResearchProposalIndex();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1.8e24);
        gov.voteOnResearch(id, addr2, true, 8e23);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        gov.finalizeVotingResearchProposal(id);
        (, , GovernorResearch.ProposalStatus status, , , ) = gov
            .getResearchProposalInfo(id);
        assertTrue(status == GovernorResearch.ProposalStatus.Scheduled);
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsFinalized() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1.8e24);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0
        );
        uint256 id = gov.getResearchProposalIndex();
        gov.voteOnResearch(id, addr2, true, 8e23);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        vm.warp(4.1 weeks);
        gov.finalizeVotingResearchProposal(id);
        vm.stopPrank();
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1));
        gov.voteOnResearch(id, addr2, true, 1.2e23);
        vm.stopPrank();
    }

    function test_RevertFreeTokensWhenVotesLocked() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 120e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.voteOnResearch(1, addr2, true, 1800e18);
        vm.stopPrank();
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        bytes4 selector = bytes4(
            keccak256("TokensStillLocked(uint256,uint256)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(selector, voteLockEnd, block.timestamp)
        );
        vm.startPrank(addr2);
        staking.free(address(sci), addr2, 1400e18);
        vm.stopPrank();
    }

    function test_FreeTokensAterVotingAndAfterVoteLockEndPassed() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 120e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.voteOnResearch(1, addr2, true, 1800e18);
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        vm.warp(voteLockEnd);
        staking.free(address(sci), addr2, 1800e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingUsdc() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            5000000e6,
            0,
            0
        );
        gov.voteOnResearch(1, addr2, true, 1800e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        uint256 id = gov.getResearchProposalIndex();
        vm.warp(4.1 weeks);
        gov.finalizeVotingResearchProposal(id);
        (, address wallet, , uint256 amounts) = gov
            .getResearchProposalProjectInfo(id);

        gov.executeOperationsProposal(id);
        (, , GovernorResearch.ProposalStatus status, , , ) = gov
            .getResearchProposalInfo(id);

        assertTrue(status == GovernorResearch.ProposalStatus.Executed);
        assertEq(usdc.balanceOf(wallet), amounts);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingSCI() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            0,
            0,
            1000e18
        );
        uint256 id = gov.getResearchProposalIndex();
        gov.voteOnResearch(id, addr2, true, 1800e18);
        vm.warp(4.1 weeks);
        gov.finalizeVotingResearchProposal(id);
        gov.executeOperationsProposal(id);

        (, address receivingWallet, , ) = gov.getResearchProposalProjectInfo(
            id
        );

        assertEq(sci.balanceOf(receivingWallet), 1000e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingCoin() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            0,
            1 ether,
            0
        );
        uint256 id = gov.getResearchProposalIndex();
        gov.voteOnResearch(id, addr2, true, 1800e18);
        vm.warp(4.1 weeks);
        gov.finalizeVotingResearchProposal(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        gov.executeOperationsProposal{value: 1 ether}(id);

        (, address receivingWallet, , ) = gov.getResearchProposalProjectInfo(
            id
        );

        assertEq(receivingWallet.balance, 1 ether);
        vm.stopPrank();
    }

    function test_RevertExecutionIfIncorrectMsgValue() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            0,
            500 ether,
            0
        );
        gov.voteOnResearch(1, addr2, true, 1800e18);
        uint256 id = gov.getResearchProposalIndex();
        vm.warp(4.1 weeks);
        gov.finalizeVotingResearchProposal(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        //for ether transactions, donation or treasury wallet is needed.
        bytes4 selector = bytes4(keccak256("IncorrectCoinValue()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        gov.executeOperationsProposal{value: 501 ether}(id);
        vm.stopPrank();
    }

    function test_RevertProposalExecutionFunctionIfIncorrectPhase() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 2000e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            0,
            500 ether,
            0
        );
        gov.voteOnResearch(1, addr2, true, 2000e18);
        uint256 id = gov.getResearchProposalIndex();
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, GovernorResearch.ProposalStatus.Active)
        );
        gov.executeOperationsProposal{value: 500 ether}(id);
        vm.expectRevert(
            abi.encodeWithSelector(selector, GovernorResearch.ProposalStatus.Active)
        );
        gov.executeOperationsProposal{value: 500 ether}(id);
        vm.stopPrank();
    }

    function test_CancelOperationsProposal() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 2000e18);
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            0,
            500 ether,
            0
        );
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        uint256 id = gov.getResearchProposalIndex();
        gov.cancelOperationsProposal(id);
        (, , GovernorResearch.ProposalStatus status, , , ) = gov
            .getResearchProposalInfo(id);
        assertTrue(status == GovernorResearch.ProposalStatus.Cancelled);
        vm.stopPrank();
    }

    function test_CompleteProposalIfNotExecutable() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 2000e18);
        gov.proposeResearch("Introduction", address(0), 0, 0, 0, false);
        uint256 id = gov.getResearchProposalIndex();
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 2000e18);
        gov.voteOnResearch(id, addr2, true, 2000e18);
        vm.stopPrank();
        vm.warp(4.1 weeks);
        gov.finalizeVotingResearchProposal(id);
        vm.startPrank(treasuryWallet);
        gov.completeOperationsProposal(id);
        (, , GovernorResearch.ProposalStatus status, , , ) = gov
            .getResearchProposalInfo(id);
        assertTrue(status == GovernorResearch.ProposalStatus.Completed);
        vm.stopPrank();
    }

    function test_RevertNonExecutableProposalIfPaymentProvided() public {
        vm.startPrank(addr1);
        bytes4 selector = bytes4(keccak256("WrongInput()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            500000e6,
            0,
            0
        );
        vm.stopPrank();
    }

    function test_TerminateGovernorAndStakingSmartContracts() public {
        vm.startPrank(treasuryWallet);
        gov.terminate();
        vm.stopPrank();
        assertEq(gov.terminated(), true);
        vm.startPrank(addr1);
        bytes4 selector = bytes4(
            keccak256("ContractTerminated(address,uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, addr1, block.number));
        staking.lock(address(sci), addr1, 2000e18);

        vm.expectRevert(abi.encodeWithSelector(selector, addr1, block.number));
        gov.proposeResearch(
            "Introduction",
            researchWallet,
            500000e6,
            0,
            0
        );
        vm.stopPrank();
    }

    function test_FreeTokensEvenIfTerminatedAndVoteLocked() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 2000e18);
        gov.proposeResearch("Introduction", address(0), 0, 0, 0, false);
        uint256 id = gov.getResearchProposalIndex();
        gov.voteOnResearch(id, addr1, true, 2000e18);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
        gov.terminate();
        vm.stopPrank();

        vm.startPrank(addr1);
        staking.free(address(sci), addr1, 2000e18);
        vm.stopPrank();
        (
            uint256 stakedPo,
            uint256 stakedSci,
            uint256 votingRights,
            uint256 voteLockEnd,
            uint256 amtSnapshots,
            address delegate
        ) = staking.users(addr1);
        assertEq(staking.getTotalStaked(), 0);
        assertEq(stakedPo, 0);
        assertEq(stakedSci, 0);
        assertEq(votingRights, 0);
        assertEq(voteLockEnd, 0);
        assertEq(amtSnapshots, 1);
        assertEq(delegate, address(0));
    }
}
