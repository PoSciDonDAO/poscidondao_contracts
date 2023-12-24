// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/Governor.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/SCI.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/staking/Staking.sol";

contract GovernorTest is Test {
    Governor public gov;
    Participation public po;
    SCI public sci;
    MockUsdc public usdc;
    Staking public staking;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address donationWallet = vm.addr(6);
    address treasuryWallet = vm.addr(7);
    address royaltyAddress = vm.addr(8);
    address researchWallet = vm.addr(9);
    address operationWallet = vm.addr(10);

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
        sci = new SCI(treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        po = new Participation("", treasuryWallet, address(staking));

        staking.setPoToken(address(po));
        staking.setSciToken(address(sci));

        gov = new Governor(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        gov.setPoToken(address(po));
        staking.setGov(address(gov));

        gov.govParams("proposalLifeTime", 4 weeks);
        gov.govParams("quorum", 100e18);
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
        assertEq(gov.quorum(), 100e18);
        assertEq(gov.voteLockTime(), 2 weeks);
    }

    function test_SetParticipationToken() public {
        vm.startPrank(treasuryWallet);
        gov.setPoToken(addr5);
        assertEq(addr5, gov.getPoToken());
        vm.stopPrank();
    }

    function test_OperationsProposalUsingUsdc() public {
        vm.startPrank(treasuryWallet);
        staking.lock(address(sci), treasuryWallet, 200e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );

        (
            uint256 startBlockNum,
            uint256 endTimeStamp,
            Governor.ProposalStatus status,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 totalVotes
        ) = gov.getOperationsProposalInfo(gov.getOperationsProposalIndex());

        assertEq(startBlockNum, block.number);
        assertEq(endTimeStamp, block.timestamp + gov.proposalLifeTime());
        assertTrue(status == Governor.ProposalStatus.Active);
        assertEq(votesFor, 0);
        assertEq(votesAgainst, 0);
        assertEq(totalVotes, 0);

        (string memory info, address wallet, , uint256 amount) = gov
            .getOperationsProposalProjectInfo(gov.getOperationsProposalIndex());

        assertEq(info, "Introduction");
        assertEq(wallet, operationWallet);
        assertEq(amount, 5000000e6);
        vm.stopPrank();
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 200e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        gov.voteOnOperations(
            gov.getOperationsProposalIndex(),
            addr1,
            true,
            100e18
        );

        (, , , uint256 votesFor, uint256 votesAgainst, uint256 totalVotes) = gov
            .getOperationsProposalInfo(gov.getOperationsProposalIndex());

        assertEq(votesFor, 100e18);
        assertEq(votesAgainst, 0);
        assertEq(totalVotes, 100e18);

        (, , , uint256 voteLockTime, , ) = staking.users(addr1);

        assertEq(voteLockTime, (block.timestamp + gov.voteLockTime()));
        vm.stopPrank();
    }

    function test_RevertVoteIfUserNotMsgSender() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 180e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
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
        uint256 id = gov.getOperationsProposalIndex();
        bytes4 selector = bytes4(keccak256("Unauthorized(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, addr3));
        gov.voteOnOperations(id, addr2, true, 100000e18);
        vm.stopPrank();
    }

    function test_RevertVoteWithVoteLockIfAlreadyVoted() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 10000e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        uint256 id = gov.getOperationsProposalIndex();
        gov.voteOnOperations(id, addr2, true, 10000e18);
        bytes4 selector = bytes4(keccak256("VoteLock()"));
        vm.expectRevert(selector);
        gov.voteOnOperations(id, addr2, true, 1800e18);
        vm.stopPrank();
    }

    function test_RevertVoteWithInsufficientRights() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 180e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        bytes4 selector = bytes4(
            keccak256("InsufficientVotingRights(uint256,uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, 180e18, 1.8e23));
        gov.voteOnOperations(1, addr2, true, 1.8e23);
        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 1.8e23);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        gov.voteOnOperations(2, addr1, true, 1.8e28);
        vm.stopPrank();
    }

    function test_RevertIfQuorumNotReached() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 180e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        uint256 id = gov.getOperationsProposalIndex();
        vm.warp(4.1 weeks);
        bytes4 selector = bytes4(keccak256("QuorumNotReached()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        gov.finalizeVotingOperationsProposal(id);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 180e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        uint256 id = gov.getOperationsProposalIndex();
        uint256 proposalLifeTime = gov.proposalLifeTime();
        bytes4 selector = bytes4(keccak256("ProposalOngoing(uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, 1, proposalLifeTime + 1)
        );
        gov.finalizeVotingOperationsProposal(id);
        vm.stopPrank();
    }

    function test_FinalizeVotingOperationsProposal() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 120e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        vm.stopPrank();
        uint256 id = gov.getOperationsProposalIndex();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1.8e24);
        gov.voteOnOperations(id, addr2, true, 8e23);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        gov.finalizeVotingOperationsProposal(id);
        (, , Governor.ProposalStatus status, , , ) = gov
            .getOperationsProposalInfo(id);
        assertTrue(status == Governor.ProposalStatus.Scheduled);
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsFinalized() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1.8e24);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        uint256 id = gov.getOperationsProposalIndex();
        gov.voteOnOperations(id, addr2, true, 8e23);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        vm.warp(4.1 weeks);
        gov.finalizeVotingOperationsProposal(id);
        vm.stopPrank();
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1));
        gov.voteOnOperations(id, addr2, true, 1.2e23);
        vm.stopPrank();
    }

    function test_RevertFreeTokensWhenVotesLocked() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 120e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.voteOnOperations(1, addr2, true, 1800e18);
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

    function test_FreeTokensAterVotingAndAfterVoteLockTimePassed() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 120e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.voteOnOperations(1, addr2, true, 1800e18);
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        vm.warp(voteLockEnd);
        staking.free(address(sci), addr2, 1800e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingUsdc() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            5000000e6,
            0,
            0,
            true
        );
        gov.voteOnOperations(1, addr2, true, 1800e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        uint256 id = gov.getOperationsProposalIndex();
        vm.warp(4.1 weeks);
        gov.finalizeVotingOperationsProposal(id);
        (, address wallet, , uint256 amounts) = gov
            .getOperationsProposalProjectInfo(id);

        gov.executeOperationsProposal(id);
        (, , Governor.ProposalStatus status, , , ) = gov
            .getOperationsProposalInfo(id);

        assertTrue(status == Governor.ProposalStatus.Executed);
        assertEq(usdc.balanceOf(wallet), amounts);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingSCI() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            0,
            0,
            1000e18,
            true
        );
        uint256 id = gov.getOperationsProposalIndex();
        gov.voteOnOperations(id, addr2, true, 1800e18);
        vm.warp(4.1 weeks);
        gov.finalizeVotingOperationsProposal(id);
        gov.executeOperationsProposal(id);

        (, address receivingWallet, , ) = gov.getOperationsProposalProjectInfo(
            id
        );

        assertEq(sci.balanceOf(receivingWallet), 1000e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingCoin() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.proposeOperation(
            "Introduction",
            researchWallet,
            0,
            1 ether,
            0,
            true
        );
        uint256 id = gov.getOperationsProposalIndex();
        gov.voteOnOperations(id, addr2, true, 1800e18);
        vm.warp(4.1 weeks);
        gov.finalizeVotingOperationsProposal(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        gov.executeOperationsProposal{value: 1 ether}(id);

        (, address receivingWallet, , ) = gov.getOperationsProposalProjectInfo(
            id
        );

        assertEq(receivingWallet.balance, 1 ether);
        vm.stopPrank();
    }

    function test_RevertExecutionIfIncorrectMsgValue() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        gov.proposeOperation(
            "Introduction",
            operationWallet,
            0,
            500 ether,
            0,
            true
        );
        gov.voteOnOperations(1, addr2, true, 1800e18);
        uint256 id = gov.getOperationsProposalIndex();
        vm.warp(4.1 weeks);
        gov.finalizeVotingOperationsProposal(id);
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
        gov.proposeOperation(
            "Introduction",
            researchWallet,
            0,
            500 ether,
            0,
            true
        );
        gov.voteOnOperations(1, addr2, true, 2000e18);
        uint256 id = gov.getOperationsProposalIndex();
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, Governor.ProposalStatus.Active)
        );
        gov.executeOperationsProposal{value: 500 ether}(id);
        vm.expectRevert(
            abi.encodeWithSelector(selector, Governor.ProposalStatus.Active)
        );
        gov.executeOperationsProposal{value: 500 ether}(id);
        vm.stopPrank();
    }

    function test_CancelOperationsProposal() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 2000e18);
        gov.proposeOperation(
            "Introduction",
            researchWallet,
            0,
            500 ether,
            0,
            true
        );
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        uint256 id = gov.getOperationsProposalIndex();
        gov.cancelOperationsProposal(id);
        (, , Governor.ProposalStatus status, , , ) = gov
            .getOperationsProposalInfo(id);
        assertTrue(status == Governor.ProposalStatus.Cancelled);
        vm.stopPrank();
    }
}
