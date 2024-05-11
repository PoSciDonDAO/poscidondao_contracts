// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/Sci.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/staking/Staking.sol";

contract GovernorResearchTest is Test {
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
    address researchWallet = vm.addr(8);
    bytes32 govIdCircuitId =
        0x729d660e1c02e4e419745e617d643f897a538673ccf1051e093bbfa58b0a120b;
    bytes32 phoneCircuitId =
        0xbce052cf723dca06a21bd3cf838bc518931730fb3db7859fc9cc86f0d5483495;

    function setUp() public {
        usdc = new MockUsdc(10000000e18);

        vm.startPrank(treasuryWallet);
        sci = new Sci(treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        po = new Participation("", treasuryWallet);

        staking.setSciToken(address(sci));

        govOps = new GovernorOperations(
            address(staking),
            treasuryWallet,
            address(usdc),
            address(sci),
            address(po),
            0x690BF2dB31D39EE0a88fcaC89117b66a588E865a
        );
        govRes = new GovernorResearch(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );
        govRes.setGovParams("proposalLifeTime", 4 weeks);
        govRes.setGovParams("quorum", 1);
        govRes.setGovParams("voteLockTime", 2 weeks);
        govRes.setGovParams("proposeLockTime", 2 weeks);

        staking.setGovRes(address(govRes));
        staking.setGovOps(address(govOps));
        vm.stopPrank();

        deal(address(sci), donationWallet, 10000000000e18);
        deal(address(usdc), donationWallet, 10000000e6);
        deal(donationWallet, 5000 ether);

        vm.startPrank(donationWallet);
        usdc.approve(address(govRes), 100000000000000e6);
        sci.approve(address(govRes), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        deal(address(sci), addr1, 10000000000e18);
        deal(address(usdc), addr1, 10000e6);
        deal(addr1, 10000 ether);
        sci.approve(address(govRes), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        staking.lock(2000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        deal(address(sci), addr2, 10000000000e18);
        deal(address(usdc), addr2, 10000e6);
        deal(addr2, 10000 ether);
        sci.approve(address(govRes), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        staking.lock(2000e18);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
        deal(address(sci), treasuryWallet, 10000000000e18);
        deal(address(usdc), treasuryWallet, 100000000e6);
        deal(treasuryWallet, 10000 ether);
        usdc.approve(address(govRes), 100000000000000e6);
        sci.approve(address(govRes), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        govRes.grantDueDiligenceRole(addr1);
        govRes.grantDueDiligenceRole(addr2);
        vm.stopPrank();
    }

    function test_SetGovParams() public {
        assertEq(govRes.proposalLifeTime(), 4 weeks);
        assertEq(govRes.quorum(), 1);
        assertEq(govRes.voteLockTime(), 2 weeks);
    }

    function test_ResearchProposalUsingUsdc() public {
        vm.startPrank(treasuryWallet);
        staking.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);

        (
            uint256 startBlockNum,
            uint256 endTimeStamp,
            GovernorResearch.ProposalStatus status,
            GovernorResearch.ProjectInfo memory details,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 totalVotes
        ) = govRes.getProposalInfo(id);

        assertEq(startBlockNum, block.number);
        assertEq(endTimeStamp, block.timestamp + govRes.proposalLifeTime());
        assertTrue(status == GovernorResearch.ProposalStatus.Active);
        assertEq(votesFor, 0);
        assertEq(votesAgainst, 0);
        assertEq(totalVotes, 0);
        assertEq(details.info, "Introduction");
        assertEq(details.receivingWallet, researchWallet);
        assertEq(details.amount, 5000000e6);
        assertEq(details.amountSci, 0);
        vm.stopPrank();
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        staking.lock(200e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        govRes.vote(id, true);

        (
            ,
            ,
            ,
            ,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 totalVotes
        ) = govRes.getProposalInfo(id);

        assertEq(votesFor, 1);
        assertEq(votesAgainst, 0);
        assertEq(totalVotes, 1);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govRes.voteLockTime()));
        vm.stopPrank();
    }

    function test_RevertVoteWithVoteLockIfAlreadyVoted() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        govRes.vote(id, true);
        bytes4 selector = bytes4(keccak256("VoteLock()"));
        vm.expectRevert(selector);
        govRes.vote(id, true);
        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {
        vm.startPrank(addr1);
        staking.lock(1.8e23);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        govRes.vote(id + 1, true);
        vm.stopPrank();
    }

    function test_RevertIfQuorumNotReached() public {
        vm.startPrank(addr1);
        staking.lock(180e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        vm.warp(4.1 weeks);
        bytes4 selector = bytes4(keccak256("QuorumNotReached()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govRes.finalize(id);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        staking.lock(180e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        uint256 proposalLifeTime = govRes.proposalLifeTime();
        bytes4 selector = bytes4(
            keccak256("ProposalOngoing(uint256,uint256,uint256)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                selector,
                id,
                block.timestamp,
                proposalLifeTime + 1
            )
        );
        govRes.finalize(id);
        vm.stopPrank();
    }

    function test_FinalizeProposal() public {
        vm.startPrank(addr1);
        staking.lock(120e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        vm.stopPrank();
        vm.startPrank(addr2);
        govRes.vote(id, true);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        govRes.finalize(id);
        (, , GovernorResearch.ProposalStatus status, , , , ) = govRes
            .getProposalInfo(id);
        assertTrue(status == GovernorResearch.ProposalStatus.Scheduled);
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsFinalized() public {
        vm.startPrank(addr2);
        // staking.lock(1.8e24);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        govRes.vote(id, true);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        vm.warp(4.1 weeks);
        govRes.finalize(id);
        vm.stopPrank();
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1));
        govRes.vote(id, true);
        vm.stopPrank();
    }

    function test_RevertFreeTokensWhenVotesLocked() public {
        vm.startPrank(addr1);
        staking.lock(1200e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        vm.stopPrank();
        vm.startPrank(addr2);
        govRes.vote(id, true);
        vm.stopPrank();
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        bytes4 selector = bytes4(
            keccak256("TokensStillLocked(uint256,uint256)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(selector, voteLockEnd, block.timestamp)
        );
        vm.startPrank(addr2);
        staking.free(1400e18);
        vm.stopPrank();
    }

    function test_FreeTokensAterVotingAndAfterVoteLockEndPassed() public {
        vm.startPrank(addr1);
        staking.lock(1200e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        vm.stopPrank();
        vm.startPrank(addr2);
        govRes.vote(id, true);
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        vm.warp(voteLockEnd);
        staking.free(1200e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingUsdc() public {
        vm.startPrank(addr2);
        staking.lock(1800e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 5000000e6, 0, 0);
        govRes.vote(id, true);
        vm.stopPrank();

        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        govRes.finalize(id);

        govRes.execute(id, false);
        (
            ,
            ,
            GovernorResearch.ProposalStatus status,
            GovernorResearch.ProjectInfo memory details,
            ,
            ,

        ) = govRes.getProposalInfo(id);
        assertTrue(status == GovernorResearch.ProposalStatus.Executed);
        assertEq(usdc.balanceOf(details.receivingWallet), details.amount);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingSci() public {
        vm.startPrank(addr2);
        staking.lock(1800e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 0, 0, 1000e18);
        govRes.vote(id, true);
        vm.warp(4.1 weeks);
        govRes.finalize(id);
        govRes.execute(id, false);

        (, , , GovernorResearch.ProjectInfo memory details, , , ) = govRes
            .getProposalInfo(id);

        assertEq(sci.balanceOf(details.receivingWallet), 1000e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingCoin() public {
        vm.startPrank(addr2);
        staking.lock(1800e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 0, 1 ether, 0);
        govRes.vote(id, true);
        vm.warp(4.1 weeks);
        govRes.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govRes.execute{value: 1 ether}(id, false);

        (, , , GovernorResearch.ProjectInfo memory details, , , ) = govRes
            .getProposalInfo(id);

        assertEq(details.receivingWallet.balance, 1 ether);
        vm.stopPrank();
    }

    function test_RevertExecutionIfIncorrectMsgValue() public {
        vm.startPrank(addr2);
        staking.lock(1800e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 0, 500 ether, 0);
        govRes.vote(id, true);
        vm.warp(4.1 weeks);
        govRes.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        //for ether transactions, donation or treasury wallet is needed.
        bytes4 selector = bytes4(keccak256("IncorrectCoinValue()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govRes.execute{value: 501 ether}(id, false);
        vm.stopPrank();
    }

    function test_RevertExecutionIfIncorrectPhase() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 0, 500 ether, 0);
        govRes.vote(id, true);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(
            abi.encodeWithSelector(
                selector,
                GovernorResearch.ProposalStatus.Active
            )
        );
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govRes.execute{value: 500 ether}(id, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                selector,
                GovernorResearch.ProposalStatus.Active
            )
        );
        govRes.execute{value: 500 ether}(id, false);
        vm.stopPrank();
    }

    function test_CancelResearchProposal() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 0, 500 ether, 0);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govRes.cancel(id);
        (, , GovernorResearch.ProposalStatus status, , , , ) = govRes
            .getProposalInfo(id);
        assertTrue(status == GovernorResearch.ProposalStatus.Cancelled);
        vm.stopPrank();
    }

    function test_TerminateResearchFunding() public {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Introduction", researchWallet, 50000e6, 0, 0);
        govRes.vote(id, true);
        govRes.burnForTerminatingResearchFunding(19000000e18);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govRes.terminateResearchFunding();
        vm.stopPrank();
        assertEq(govRes.terminated(), true);
        vm.startPrank(addr1);
        bytes4 selector = bytes4(keccak256("ContractTerminated(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, block.number));
        govRes.propose("Introduction", researchWallet, 500000e6, 0, 0);
        vm.stopPrank();
    }
}
