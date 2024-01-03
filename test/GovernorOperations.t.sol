// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/Sci.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/staking/Staking.sol";

contract GovernorOperationsTest is Test {
    GovernorOperations public govOps;
    GovernorResearch public govRes;
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
    address royaltyAddress = vm.addr(8);
    address operationsWallet = vm.addr(9);

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

        govOps = new GovernorOperations(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        govRes = new GovernorResearch(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        govOps.setPoToken(address(po));
        staking.setGovOps(address(govOps));
        staking.setGovRes(address(govRes));
        govOps.govParams("proposalLifeTime", 4 weeks);
        govOps.govParams("quorum", 100e18);
        govOps.govParams("voteLockTime", 2 weeks);
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
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();

        vm.startPrank(donationWallet);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();
    }

    function test_SetGovParams() public {
        assertEq(govOps.proposalLifeTime(), 4 weeks);
        assertEq(govOps.quorum(), 100e18);
        assertEq(govOps.voteLockTime(), 2 weeks);
    }

    function test_SetParticipationToken() public {
        vm.startPrank(treasuryWallet);
        govOps.setPoToken(addr5);
        assertEq(addr5, govOps.getPoToken());
        vm.stopPrank();
    }

    function test_OperationsProposalUsingUsdc() public {
        vm.startPrank(treasuryWallet);
        staking.lock(address(sci), treasuryWallet, 200e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );

        (
            uint256 startBlockNum,
            uint256 endTimeStamp,
            GovernorOperations.ProposalStatus status,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 totalVotes
        ) = govOps.getOperationsProposalInfo(govOps.getOperationsProposalIndex());

        assertEq(startBlockNum, block.number);
        assertEq(endTimeStamp, block.timestamp + govOps.proposalLifeTime());
        assertTrue(status == GovernorOperations.ProposalStatus.Active);
        assertEq(votesFor, 0);
        assertEq(votesAgainst, 0);
        assertEq(totalVotes, 0);

        (string memory info, address wallet, , uint256 amount) = govOps
            .getOperationsProposalProjectInfo(govOps.getOperationsProposalIndex());

        assertEq(info, "Introduction");
        assertEq(wallet, operationsWallet);
        assertEq(amount, 5000000e6);
        vm.stopPrank();
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 200e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        govOps.voteOnOperations(
            govOps.getOperationsProposalIndex(),
            addr1,
            true,
            100e18
        );

        (, , , uint256 votesFor, uint256 votesAgainst, uint256 totalVotes) = govOps
            .getOperationsProposalInfo(govOps.getOperationsProposalIndex());

        assertEq(votesFor, 100e18);
        assertEq(votesAgainst, 0);
        assertEq(totalVotes, 100e18);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govOps.voteLockTime()));
        vm.stopPrank();
    }

    function test_RevertVoteIfUserNotMsgSender() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 180e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
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
        uint256 id = govOps.getOperationsProposalIndex();
        bytes4 selector = bytes4(keccak256("Unauthorized(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, addr3));
        govOps.voteOnOperations(id, addr2, true, 100000e18);
        vm.stopPrank();
    }

    function test_RevertVoteWithVoteLockIfAlreadyVoted() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 10000e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        uint256 id = govOps.getOperationsProposalIndex();
        govOps.voteOnOperations(id, addr2, true, 10000e18);
        bytes4 selector = bytes4(keccak256("VoteLock()"));
        vm.expectRevert(selector);
        govOps.voteOnOperations(id, addr2, true, 1800e18);
        vm.stopPrank();
    }

    function test_RevertVoteWithInsufficientRights() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 180e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        bytes4 selector = bytes4(
            keccak256("InsufficientVotingRights(uint256,uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, 180e18, 1.8e23));
        govOps.voteOnOperations(1, addr2, true, 1.8e23);
        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 1.8e23);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        govOps.voteOnOperations(2, addr1, true, 1.8e28);
        vm.stopPrank();
    }

    function test_RevertIfQuorumNotReached() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 180e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        uint256 id = govOps.getOperationsProposalIndex();
        vm.warp(4.1 weeks);
        bytes4 selector = bytes4(keccak256("QuorumNotReached()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.finalizeVotingOperationsProposal(id);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 180e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        uint256 id = govOps.getOperationsProposalIndex();
        uint256 proposalLifeTime = govOps.proposalLifeTime();
        bytes4 selector = bytes4(keccak256("ProposalOngoing(uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, 1, proposalLifeTime + 1)
        );
        govOps.finalizeVotingOperationsProposal(id);
        vm.stopPrank();
    }

    function test_FinalizeVotingOperationsProposal() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 120e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        vm.stopPrank();
        uint256 id = govOps.getOperationsProposalIndex();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1.8e24);
        govOps.voteOnOperations(id, addr2, true, 8e23);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        govOps.finalizeVotingOperationsProposal(id);
        (, , GovernorOperations.ProposalStatus status, , , ) = govOps
            .getOperationsProposalInfo(id);
        assertTrue(status == GovernorOperations.ProposalStatus.Scheduled);
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsFinalized() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1.8e24);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        uint256 id = govOps.getOperationsProposalIndex();
        govOps.voteOnOperations(id, addr2, true, 8e23);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        vm.warp(4.1 weeks);
        govOps.finalizeVotingOperationsProposal(id);
        vm.stopPrank();
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1));
        govOps.voteOnOperations(id, addr2, true, 1.2e23);
        vm.stopPrank();
    }

    function test_RevertFreeTokensWhenVotesLocked() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 120e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        govOps.voteOnOperations(1, addr2, true, 1800e18);
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
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        govOps.voteOnOperations(1, addr2, true, 1800e18);
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        vm.warp(voteLockEnd);
        staking.free(address(sci), addr2, 1800e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingUsdc() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            5000000e6,
            0,
            0,
            true
        );
        govOps.voteOnOperations(1, addr2, true, 1800e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        uint256 id = govOps.getOperationsProposalIndex();
        vm.warp(4.1 weeks);
        govOps.finalizeVotingOperationsProposal(id);
        (, address wallet, , uint256 amounts) = govOps
            .getOperationsProposalProjectInfo(id);

        govOps.executeOperationsProposal(id);
        (, , GovernorOperations.ProposalStatus status, , , ) = govOps
            .getOperationsProposalInfo(id);

        assertTrue(status == GovernorOperations.ProposalStatus.Executed);
        assertEq(usdc.balanceOf(wallet), amounts);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingSCI() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            0,
            0,
            1000e18,
            true
        );
        uint256 id = govOps.getOperationsProposalIndex();
        govOps.voteOnOperations(id, addr2, true, 1800e18);
        vm.warp(4.1 weeks);
        govOps.finalizeVotingOperationsProposal(id);
        govOps.executeOperationsProposal(id);

        (, address receivingWallet, , ) = govOps.getOperationsProposalProjectInfo(
            id
        );

        assertEq(sci.balanceOf(receivingWallet), 1000e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingCoin() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            0,
            1 ether,
            0,
            true
        );
        uint256 id = govOps.getOperationsProposalIndex();
        govOps.voteOnOperations(id, addr2, true, 1800e18);
        vm.warp(4.1 weeks);
        govOps.finalizeVotingOperationsProposal(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.executeOperationsProposal{value: 1 ether}(id);

        (, address receivingWallet, , ) = govOps.getOperationsProposalProjectInfo(
            id
        );

        assertEq(receivingWallet.balance, 1 ether);
        vm.stopPrank();
    }

    function test_RevertExecutionIfIncorrectMsgValue() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 1800e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            0,
            500 ether,
            0,
            true
        );
        govOps.voteOnOperations(1, addr2, true, 1800e18);
        uint256 id = govOps.getOperationsProposalIndex();
        vm.warp(4.1 weeks);
        govOps.finalizeVotingOperationsProposal(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        //for ether transactions, donation or treasury wallet is needed.
        bytes4 selector = bytes4(keccak256("IncorrectCoinValue()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.executeOperationsProposal{value: 501 ether}(id);
        vm.stopPrank();
    }

    function test_RevertProposalExecutionFunctionIfIncorrectPhase() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 2000e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            0,
            500 ether,
            0,
            true
        );
        govOps.voteOnOperations(1, addr2, true, 2000e18);
        uint256 id = govOps.getOperationsProposalIndex();
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(
            abi.encodeWithSelector(selector, GovernorOperations.ProposalStatus.Active)
        );
        govOps.executeOperationsProposal{value: 500 ether}(id);
        vm.expectRevert(
            abi.encodeWithSelector(selector, GovernorOperations.ProposalStatus.Active)
        );
        govOps.executeOperationsProposal{value: 500 ether}(id);
        vm.stopPrank();
    }

    function test_CancelOperationsProposal() public {
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 2000e18);
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            0,
            500 ether,
            0,
            true
        );
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        uint256 id = govOps.getOperationsProposalIndex();
        govOps.cancelOperationsProposal(id);
        (, , GovernorOperations.ProposalStatus status, , , ) = govOps
            .getOperationsProposalInfo(id);
        assertTrue(status == GovernorOperations.ProposalStatus.Cancelled);
        vm.stopPrank();
    }

    function test_CompleteProposalIfNotExecutable() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 2000e18);
        govOps.proposeOperation("Introduction", address(0), 0, 0, 0, false);
        uint256 id = govOps.getOperationsProposalIndex();
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(address(sci), addr2, 2000e18);
        govOps.voteOnOperations(id, addr2, true, 2000e18);
        vm.stopPrank();
        vm.warp(4.1 weeks);
        govOps.finalizeVotingOperationsProposal(id);
        vm.startPrank(treasuryWallet);
        govOps.completeOperationsProposal(id);
        (, , GovernorOperations.ProposalStatus status, , , ) = govOps
            .getOperationsProposalInfo(id);
        assertTrue(status == GovernorOperations.ProposalStatus.Completed);
        vm.stopPrank();
    }

    function test_RevertProposalIfInfoEmpty() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 2000e18);
        bytes4 selector = bytes4(keccak256("InvalidInfo()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.proposeOperation(
            "",
            operationsWallet,
            500000e6,
            0,
            0,
            false
        );
        vm.stopPrank();
    }

    function test_RevertNonExecutableProposalIfPaymentProvided() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 2000e18);
        bytes4 selector = bytes4(keccak256("InvalidInputForNonExecutable()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            500000e6,
            0,
            0,
            false
        );
        vm.stopPrank();
    }

    function test_RevertExecutableProposalIfNoPaymentAndWalletProvided() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 2000e18);
        bytes4 selector = bytes4(keccak256("InvalidInputForExecutable()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.proposeOperation(
            "Introduction",
            address(0),
            0,
            0,
            0,
            true
        );
        vm.stopPrank();
    }

    function test_RevertExecutableProposalIfNoPaymentButWalletProvided() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 2000e18);
        bytes4 selector = bytes4(keccak256("InvalidInputForExecutable()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            0,
            0,
            0,
            true
        );
        vm.stopPrank();
    }

    function test_TerminateGovernorAndStakingSmartContracts() public {
        vm.startPrank(treasuryWallet);
        govOps.terminateOperations();
        govRes.terminateResearch();
        vm.stopPrank();
        assertEq(govOps.terminated(), true);
        assertEq(govRes.terminated(), true);
        vm.startPrank(addr1);
        bytes4 selector = bytes4(
            keccak256("ContractsTerminated()")
        );
        vm.expectRevert(abi.encodeWithSelector(selector));
        staking.lock(address(sci), addr1, 2000e18);
        bytes4 selector1 = bytes4(
            keccak256("ContractTerminated(uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector1, block.number));
        govOps.proposeOperation(
            "Introduction",
            operationsWallet,
            500000e6,
            0,
            0,
            false
        );
        vm.stopPrank();
    }

    function test_FreeTokensEvenIfTerminatedAndVoteLocked() public {
        vm.startPrank(addr1);
        staking.lock(address(sci), addr1, 2000e18);
        govOps.proposeOperation("Introduction", address(0), 0, 0, 0, false);
        uint256 id = govOps.getOperationsProposalIndex();
        govOps.voteOnOperations(id, addr1, true, 2000e18);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
        govOps.terminateOperations();
        govRes.terminateResearch();
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
