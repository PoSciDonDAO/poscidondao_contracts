// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/test/Usdc.sol";
import "contracts/tokens/Sci.sol";
import "contracts/tokens/Po.sol";
import "contracts/exchange/PoToSciExchange.sol";
import "contracts/sciManager/SciManager.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/executors/Transaction.sol";
import "contracts/executors/Election.sol";
import "contracts/executors/Impeachment.sol";
import "contracts/executors/ParameterChange.sol";
import "contracts/governance/GovernorExecutor.sol";
import "contracts/governance/GovernorGuard.sol";
import "forge-std/console2.sol";
import "contracts/DeployedAddresses.sol";

contract GovernorResearchTest is Test {
    Usdc usdc;
    Sci sci;
    Po po;
    PoToSciExchange exchange;
    SciManager sciManager;
    GovernorOperations govOps;
    GovernorResearch govRes;
    GovernorExecutor executor;
    GovernorGuard guard;
    Transaction transaction;
    Election election;
    ParameterChange govParams;
    GovernorGuard guardOps;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address researchFundingWallet = vm.addr(6);
    address test = 0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe;
    address admin = DeployedAddresses.admin;
    address researchersWallet = vm.addr(8);
    address signer = vm.addr(9);

    function setUp() public {
        usdc = Usdc(DeployedAddresses.usdc);

        vm.startPrank(admin);
        sci = Sci(DeployedAddresses.sci);
        po = Po(DeployedAddresses.po);
        exchange = PoToSciExchange(DeployedAddresses.poToSciExchange);
        sciManager = SciManager(DeployedAddresses.sciManager);
        govOps = GovernorOperations(DeployedAddresses.governorOperations);
        govRes = GovernorResearch(DeployedAddresses.governorResearch);

        address[] memory governors = new address[](2);
        governors[0] = address(govOps);
        governors[1] = address(govRes);

        executor = GovernorExecutor(DeployedAddresses.governorExecutor);
        guard = GovernorGuard(DeployedAddresses.governorGuard);

        govOps.setGovExec(address(executor));
        govRes.setGovExec(address(executor));
        govRes.setGovGuard(address(guard));
        govParams = new ParameterChange(address(govOps), address(executor), "quorum", 3);

        transaction = new Transaction(
            researchFundingWallet,
            researchersWallet,
            10000e6,
            5000e18,
            address(executor)
        );

        sci.approve(address(govOps), 100000000000000e18);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(executor), 100000000000000e18);
        usdc.approve(address(executor), 100000000000000e6);
        sci.approve(address(transaction), 100000000000000e18);
        usdc.approve(address(transaction), 100000000000000e6);
        sci.approve(address(sciManager), 1000000000000e18);
        deal(address(usdc), admin, 100000000e6);
        deal(address(sci), admin, 10000000e18);

        po.setGovOps(address(govOps));
        sciManager.setGovOps(address(govOps));
        sciManager.setGovRes(address(govRes));
        govOps.setGovExec(address(executor));
        govOps.setGovGuard(address(guard));
        sciManager.setGovExec(address(executor));
        govRes.setGovExec(address(executor));
        govRes.setGovGuard(address(guard));
        vm.stopPrank();

        vm.startPrank(researchFundingWallet);
        usdc.approve(address(govRes), 100000000000000e6);
        sci.approve(address(govRes), 100000000000000e18);
        sci.approve(address(sciManager), 1000000000000e18);
        sci.approve(address(transaction), 100000000000000e18);
        usdc.approve(address(transaction), 100000000000000e6);
        deal(address(usdc), researchFundingWallet, 100000000e6);
        deal(address(sci), researchFundingWallet, 10000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        deal(address(sci), addr1, 10000000000e18);
        deal(address(usdc), addr1, 10000e6);
        sci.approve(address(govRes), 1000000000000e18);
        sci.approve(address(sciManager), 1000000000000e18);
        sciManager.lock(2000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        deal(address(sci), addr2, 10000000000e18);
        deal(address(usdc), addr2, 10000e6);
        sci.approve(address(govRes), 1000000000000e18);
        sci.approve(address(sciManager), 1000000000000e18);
        sciManager.lock(2000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        sciManager.lock(2000e18);
        vm.stopPrank();

        vm.startPrank(researchFundingWallet);
        sciManager.lock(1000e18);
        vm.stopPrank();
        vm.startPrank(addr2);
        sciManager.lock(1000e18);
        vm.stopPrank();
        vm.startPrank(addr1);
        address[] memory electedMembers = new address[](2);
        electedMembers[0] = addr1;
        electedMembers[1] = addr2;
        election = new Election(
            electedMembers,
            address(govRes),
            address(executor)
        );

        vm.stopPrank();
        vm.startPrank(admin);
        sciManager.lock(1000e18);
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(election), false);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();
    }

    function test_CreateResearchProposal() public {
        vm.startPrank(admin);
        sciManager.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));

        GovernorResearch.Proposal memory proposal = govRes.getProposal(id);

        assertEq(proposal.info, "Info");
        assertEq(proposal.startBlockNum, block.number);
        assertEq(
            proposal.endTimestamp,
            block.timestamp + govRes.getGovernanceParameters().proposalLifetime
        );
        assertEq(
            uint(proposal.status),
            uint(GovernorResearch.ProposalStatus.Active)
        );
        assertEq(proposal.action, address(transaction));
        assertEq(proposal.votesFor, 0);
        assertEq(proposal.votesAgainst, 0);
        assertEq(proposal.votesTotal, 0);
        assertEq(proposal.executable, true);
        vm.stopPrank();
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        sciManager.lock(200e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));
        govRes.vote(id, true);
        GovernorResearch.Proposal memory proposal = govRes.getProposal(id);

        assertEq(proposal.votesFor, 1);
        assertEq(proposal.votesTotal, 1);

        (, , , uint256 voteLockEnd, ) = sciManager.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govRes.getGovernanceParameters().voteLockTime));
        vm.stopPrank();
    }

    function test_SuccessfulVoteChangeWithinWindow() public {
        vm.startPrank(addr2);
        sciManager.lock(10000e18);

        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));

        govRes.vote(id, true);

        vm.warp(govRes.getGovernanceParameters().voteChangeTime - 1);

        govRes.vote(id, false);

        GovernorResearch.UserVoteData memory userVoteData = govRes
            .getUserVoteData(addr2, id);
        assertEq(userVoteData.previousSupport, false);

        vm.stopPrank();
    }

    function test_RevertVoteIfVoteChangeCutOffPassed() public {
        vm.startPrank(addr2);
        sciManager.lock(10000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));
        vm.warp(
            block.timestamp +
                govRes.getGovernanceParameters().proposalLifetime -
                govRes.getGovernanceParameters().voteChangeCutOff +
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
        sciManager.lock(10000e18);
        vm.warp(block.timestamp);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));

        govRes.vote(id, true);

        vm.warp(block.timestamp + govRes.getGovernanceParameters().voteChangeTime + 1);

        bytes4 selector = bytes4(keccak256("VoteChangeWindowExpired()"));
        vm.expectRevert(selector);

        govRes.vote(id, false);

        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {
        vm.startPrank(addr1);
        sciManager.lock(1.8e23);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        govRes.vote(id + 1, true);
        vm.stopPrank();
    }

    function test_RevertIfQuorumNotReached() public {
        vm.startPrank(addr1);
        sciManager.lock(180e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));

        vm.warp(block.timestamp + 4.1 weeks);
        uint256 quorum = govRes.getGovernanceParameters().quorum;
        bytes4 selector = bytes4(
            keccak256("QuorumNotReached(uint256,uint256,uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, id, 0, quorum));
        govRes.schedule(id);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        sciManager.lock(180e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));

        uint256 proposalLifetime = govRes.getGovernanceParameters().proposalLifetime;
        bytes4 selector = bytes4(
            keccak256("ProposalOngoing(uint256,uint256,uint256)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                selector,
                id,
                block.timestamp,
                block.timestamp + proposalLifetime
            )
        );
        govRes.schedule(id);
        vm.stopPrank();
    }

    function test_ScheduleProposal() public {
        vm.startPrank(addr1);
        sciManager.lock(120e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));
        vm.stopPrank();
        vm.startPrank(addr2);
        govRes.vote(id, true);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
        GovernorResearch.Proposal memory proposal = govRes.getProposal(id);
        assertTrue(
            proposal.status == GovernorResearch.ProposalStatus.Scheduled
        );
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsScheduled() public {
        vm.startPrank(addr2);
        // sciManager.lock(1.8e24);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));
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
        sciManager.lock(1200e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));
        vm.stopPrank();
        vm.startPrank(addr2);
        govRes.vote(id, true);
        vm.stopPrank();
        (, , , uint256 voteLockEnd, ) = sciManager.users(addr2);
        bytes4 selector = bytes4(
            keccak256("TokensStillLocked(uint256,uint256)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(selector, voteLockEnd, block.timestamp)
        );
        vm.startPrank(addr2);
        sciManager.free(1400e18);
        vm.stopPrank();
    }

    function test_FreeTokensAterVotingAndAfterVoteLockEndPassed() public {
        vm.startPrank(addr1);
        sciManager.lock(1200e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));
        vm.stopPrank();
        vm.startPrank(addr2);
        govRes.vote(id, true);
        (, , , uint256 voteLockEnd, ) = sciManager.users(addr2);
        vm.warp(voteLockEnd);
        sciManager.free(1200e18);
        vm.stopPrank();
    }

    function test_ExecuteProposal() public {
        vm.startPrank(addr2);
        sciManager.lock(1800e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));
        govRes.vote(id, true);
        vm.stopPrank();

        vm.startPrank(addr1);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govRes.execute(id);
        GovernorResearch.Proposal memory proposal2 = govRes.getProposal(id);

        assertTrue(
            proposal2.status == GovernorResearch.ProposalStatus.Executed
        );
        assertEq(usdc.balanceOf(researchersWallet), 10000e6);
        assertEq(sci.balanceOf(researchersWallet), 5000e18);
        vm.stopPrank();
    }

    function test_CompleteProposal() public {
        vm.startPrank(addr2);
        sciManager.lock(1800e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(0));
        govRes.vote(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
        govRes.complete(id);
        GovernorResearch.Proposal memory proposal = govRes.getProposal(id);

        assertTrue(
            proposal.status == GovernorResearch.ProposalStatus.Completed
        );
        vm.stopPrank();
    }

    function test_RevertExecutionIfIncorrectPhase() public {
        vm.startPrank(addr2);
        sciManager.lock(2000e18);
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

    function test_CancelMaliciousExecutableProposal() public {
        vm.startPrank(addr2);
        sciManager.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(transaction));
        govRes.vote(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
        vm.startPrank(admin);
        guard.cancelRes(id);
        vm.stopPrank();
        GovernorResearch.Proposal memory proposal = govRes.getProposal(id);
        assertTrue(proposal.status == GovernorResearch.ProposalStatus.Canceled);
        vm.stopPrank();
    }

    function test_CancelMaliciousCompletableProposal() public {
        vm.startPrank(addr2);
        sciManager.lock(2000e18);
        uint256 id = govRes.getProposalIndex();
        govRes.propose("Info", address(0));
        govRes.vote(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govRes.schedule(id);
        vm.startPrank(admin);
        guard.cancelRes(id);
        vm.stopPrank();
        GovernorResearch.Proposal memory proposal = govRes.getProposal(id);
        assertTrue(proposal.status == GovernorResearch.ProposalStatus.Canceled);
        vm.stopPrank();
    }

    function test_CancelRejectedProposal() public {
        vm.startPrank(addr2);
        sciManager.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(10000e18);
        govOps.voteStandard(id, false);
        vm.warp(4.1 weeks);
        govOps.cancelRejected(id);
        GovernorOperations.Proposal memory proposal = govOps.getProposal(
            id
        );
        assertTrue(
            proposal.status == GovernorOperations.ProposalStatus.Canceled
        );
        vm.stopPrank();
    }
}
