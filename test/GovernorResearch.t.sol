// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/tokens/Sci.sol";
import "contracts/tokens/Po.sol";
import "contracts/exchange/PoToSciExchange.sol";
import "contracts/staking/Staking.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/executors/Transaction.sol";
import "contracts/executors/Election.sol";
import "contracts/executors/Impeachment.sol";
import "contracts/executors/GovernorParameters.sol";
import "contracts/governance/GovernorExecutor.sol";
import "contracts/governance/GovernorGuard.sol";
import "forge-std/console2.sol";

contract GovernorResearchTest is Test {
    MockUsdc usdc;
    Sci sci;
    Po po;
    PoToSciExchange exchange;
    Staking staking;
    GovernorOperations govOps;
    GovernorResearch govRes;
    GovernorExecutor executor;
    GovernorGuard guardRes;
    Transaction transactionRes;
    Election electionOps;
    GovernorParameters govParams;
    GovernorGuard guardOps;
    Transaction transactionOps;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address researchFundingWallet = vm.addr(6);
    address admin = vm.addr(7);
    address researchersWallet = vm.addr(8);
    address signer = vm.addr(9);
    bytes32 govIdCircuitId =
        0x729d660e1c02e4e419745e617d643f897a538673ccf1051e093bbfa58b0a120b;
    bytes32 phoneCircuitId =
        0xbce052cf723dca06a21bd3cf838bc518931730fb3db7859fc9cc86f0d5483495;

    function setUp() public {
        usdc = new MockUsdc(10000000e18);

        vm.startPrank(admin);

        sci = new Sci(admin, 18910000);

        po = new Po("https://mock-uri.io/", admin);

        exchange = new PoToSciExchange(admin, address(sci), address(po));

        staking = new Staking(admin, address(sci));

        govRes = new GovernorResearch(
            address(staking),
            admin,
            researchFundingWallet,
            address(usdc),
            address(sci)
        );

        govOps = new GovernorOperations(
            address(staking),
            admin,
            address(sci),
            address(po),
            signer,
            address(govRes)
        );

        guardRes = new GovernorGuard(admin, address(govRes));

        address[] memory governors = new address[](2);
        governors[0] = address(govOps);
        governors[1] = address(govRes);
        executor = new GovernorExecutor(admin, 2 days, governors);
        govOps.setGovExec(address(executor));
        govRes.setGovExec(address(executor));

        govParams = new GovernorParameters(
            address(govRes),
            bytes32("quorum"),
            3
        );

        transactionRes = new Transaction(
            researchersWallet,
            10000e6,
            5000e18,
            address(executor),
            researchFundingWallet,
            address(usdc),
            address(sci)
        );

        staking.setGovRes(address(govRes));
        staking.setGovOps(address(govOps));
        po.setGovOps(address(govOps));
        govRes.setGovOps(address(govOps));

        deal(address(sci), researchFundingWallet, 10000000000e18);
        deal(address(usdc), researchFundingWallet, 10000000e6);

        govRes.setGovExec(address(executor));
        govRes.setGovGuard(address(guardRes));
        deal(address(sci), admin, 10000000000e18);
        deal(address(usdc), admin, 100000000e6);
        usdc.approve(address(govRes), 100000000000000e6);
        sci.approve(address(govRes), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();

        vm.startPrank(researchFundingWallet);
        usdc.approve(address(govRes), 100000000000000e6);
        sci.approve(address(govRes), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        sci.approve(address(transactionRes), 100000000000000e18);
        usdc.approve(address(transactionRes), 100000000000000e6);
        vm.stopPrank();

        vm.startPrank(addr1);
        deal(address(sci), addr1, 10000000000e18);
        deal(address(usdc), addr1, 10000e6);
        sci.approve(address(govRes), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        staking.lock(2000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        deal(address(sci), addr2, 10000000000e18);
        deal(address(usdc), addr2, 10000e6);
        sci.approve(address(govRes), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        staking.lock(2000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        staking.lock(2000e18);
        vm.stopPrank();

        vm.startPrank(researchFundingWallet);
        staking.lock(1000e18);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(1000e18);
        vm.stopPrank();
        vm.startPrank(addr1);
        address[] memory electedMembers = new address[](4);
        electedMembers[0] = admin;
        electedMembers[1] = researchFundingWallet;
        electedMembers[2] = addr1;
        electedMembers[3] = addr2;
        electionOps = new Election(
            electedMembers,
            address(executor),
            address(govRes)
        );
        vm.stopPrank();
        vm.startPrank(admin);
        staking.lock(1000e18);
        address[] memory governors2 = new address[](1);
        governors2[0] = address(electionOps);
        // govRes.addGovernorsAdmin(governors2);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(20000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(electionOps), false);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();
    }

    function test_ChangeGovernanceParameters() public {
        vm.startPrank(admin);
        address[] memory governors = new address[](1);
        governors[0] = address(govParams);
        // govRes.addGovernorsAdmin(governors);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(10000e18);
        uint256 id = govRes.getProposalIndex();
        (, uint256 quorum, , , , ) = govRes.getGovernanceParameters();
        assertEq(quorum, 1);
        govRes.propose("Info", address(govParams));
        govRes.vote(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govRes.execute(id);
        vm.stopPrank();
        (, uint256 quorum1, , , , ) = govRes.getGovernanceParameters();
        assertEq(quorum1, 3);
    }

    function test_CreateResearchProposal() public {
        vm.startPrank(admin);
        staking.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));

        GovernorResearch.Proposal memory proposal = govRes.getProposalInfo(id);

        assertEq(proposal.info, "Info");
        assertEq(proposal.startBlockNum, block.number);
        assertEq(
            proposal.endTimestamp,
            block.timestamp + govRes.proposalLifeTime()
        );
        assertEq(
            uint(proposal.status),
            uint(GovernorResearch.ProposalStatus.Active)
        );
        assertEq(proposal.action, address(transactionRes));
        assertEq(proposal.votesFor, 0);
        assertEq(proposal.votesAgainst, 0);
        assertEq(proposal.totalVotes, 0);
        assertEq(proposal.executable, true);
        vm.stopPrank();
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        staking.lock(200e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));
        govRes.vote(id, true);
        GovernorResearch.Proposal memory proposal = govRes.getProposalInfo(id);

        assertEq(proposal.votesFor, 1);
        assertEq(proposal.totalVotes, 1);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govRes.voteLockTime()));
        vm.stopPrank();
    }

    function test_SuccessfulVoteChangeWithinWindow() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);

        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));

        govRes.vote(id, true);

        vm.warp(govRes.voteChangeTime() - 1);

        govRes.vote(id, false);

        GovernorResearch.UserVoteData memory userVoteData = govRes
            .getUserVoteData(addr2, id);
        assertEq(userVoteData.previousSupport, false);

        vm.stopPrank();
    }

    function test_RevertVoteIfVoteChangeCutOffPassed() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));
        vm.warp(
            block.timestamp +
                govRes.proposalLifeTime() -
                govRes.voteChangeCutOff() +
                1
        );
        govRes.vote(id, true);
        bytes4 selector = bytes4(
            keccak256("VoteChangeNotAllowedAfterCutOff()")
        );
        vm.expectRevert(selector);
        govRes.vote(id, true);
        vm.stopPrank();
    }

    function test_RevertVoteIfVoteChangeWindowExpired() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        vm.warp(block.timestamp);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));

        govRes.vote(id, true);

        vm.warp(block.timestamp + govRes.voteChangeTime() + 1);

        bytes4 selector = bytes4(keccak256("VoteChangeWindowExpired()"));
        vm.expectRevert(selector);

        govRes.vote(id, false);

        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {
        vm.startPrank(addr1);
        staking.lock(1.8e23);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        govRes.vote(id + 1, true);
        vm.stopPrank();
    }

    function test_RevertIfQuorumNotReached() public {
        vm.startPrank(addr1);
        staking.lock(180e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));

        vm.warp(block.timestamp + 4.1 weeks);
        bytes4 selector = bytes4(keccak256("QuorumNotReached()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govRes.schedule(id);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        staking.lock(180e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));

        uint256 proposalLifeTime = govRes.proposalLifeTime();
        bytes4 selector = bytes4(
            keccak256("ProposalOngoing(uint256,uint256,uint256)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                selector,
                id,
                block.timestamp,
                block.timestamp + proposalLifeTime
            )
        );
        govRes.schedule(id);
        vm.stopPrank();
    }

    function test_ScheduleProposal() public {
        vm.startPrank(addr1);
        staking.lock(120e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));
        vm.stopPrank();
        vm.startPrank(addr2);
        govRes.vote(id, true);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
        GovernorResearch.Proposal memory proposal = govRes.getProposalInfo(id);
        assertTrue(
            proposal.status == GovernorResearch.ProposalStatus.Scheduled
        );
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsScheduled() public {
        vm.startPrank(addr2);
        // staking.lock(1.8e24);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));
        govRes.vote(id, true);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
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
        govRes.propose("Info", address(transactionRes));
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
        govRes.propose("Info", address(transactionRes));
        vm.stopPrank();
        vm.startPrank(addr2);
        govRes.vote(id, true);
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        vm.warp(voteLockEnd);
        staking.free(1200e18);
        vm.stopPrank();
    }

    function test_ExecuteProposal() public {
        vm.startPrank(addr2);
        staking.lock(1800e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));
        govRes.vote(id, true);
        vm.stopPrank();

        vm.startPrank(addr1);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govRes.execute(id);
        GovernorResearch.Proposal memory proposal2 = govRes.getProposalInfo(id);

        assertTrue(
            proposal2.status == GovernorResearch.ProposalStatus.Executed
        );
        assertEq(usdc.balanceOf(researchersWallet), 10000e6);
        assertEq(sci.balanceOf(researchersWallet), 5000e18);
        vm.stopPrank();
    }

    function test_CompleteProposal() public {
        vm.startPrank(addr2);
        staking.lock(1800e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(0));
        govRes.vote(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
        govRes.complete(id);
        GovernorResearch.Proposal memory proposal = govRes.getProposalInfo(id);

        assertTrue(
            proposal.status == GovernorResearch.ProposalStatus.Completed
        );
        vm.stopPrank();
    }

    function test_RevertExecutionIfIncorrectPhase() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(0));
        govRes.vote(id, true);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(
            abi.encodeWithSelector(
                selector,
                GovernorResearch.ProposalStatus.Active
            )
        );
        govRes.execute(id);
        vm.stopPrank();
    }

    function test_CancelResearchProposal() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(0));
        vm.stopPrank();
        vm.warp(block.timestamp + 4.1 weeks);
        vm.startPrank(admin);
        govRes.cancel(id);
        GovernorResearch.Proposal memory proposal = govRes.getProposalInfo(id);
        assertTrue(
            proposal.status == GovernorResearch.ProposalStatus.Cancelled
        );
        vm.stopPrank();
    }

    function test_GovOpsDoesNotWorkAfterTermination() public {
        vm.startPrank(admin);
        staking.burnForTermination(5000000e18);
        staking.terminate();
        vm.stopPrank();
        assertEq(govRes.terminated(), true);
        vm.startPrank(addr1);
        bytes4 selector1 = bytes4(keccak256("ContractTerminated(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector1, block.number));
        govRes.propose("Info", address(transactionRes));

        vm.stopPrank();
    }

    function test_CancelProposalsIfStillOngoingAfterTermination() public {
        vm.startPrank(admin);
        staking.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transactionRes));

        staking.burnForTermination(5000000e18);
        staking.terminate();
        vm.stopPrank();
        vm.startPrank(addr1);
        govRes.cancel(id);
        assertEq(govRes.terminated(), true);
        bytes4 selector1 = bytes4(keccak256("ContractTerminated(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector1, block.number));
        govRes.propose("Info", address(transactionRes));
        vm.stopPrank();
    }
}
