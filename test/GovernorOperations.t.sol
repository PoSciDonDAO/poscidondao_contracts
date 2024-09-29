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
import "contracts/executors/AddDelegate.sol";
import "forge-std/console2.sol";

contract GovernorOperationsTest is Test {
    MockUsdc usdc;
    Sci sci;
    Po po;
    PoToSciExchange exchange;
    Staking staking;
    GovernorOperations govOps;
    GovernorResearch govRes;
    GovernorExecutor executor;
    GovernorGuard guard;
    Transaction transactions;
    Election election;
    Impeachment impeachment;
    GovernorParameters govParams;
    GovernorParameters govParamsRes;
    AddDelegate addDelegate;

    address signer = vm.addr(10);
    address customAddress = signer;
    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address researchFundingWallet = vm.addr(6);
    address admin = vm.addr(7);
    address opWallet = vm.addr(8);

    event Cancelled(uint256 indexed id, bool indexed rejected);

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
            signer
        );

        address[] memory governors = new address[](2);
        governors[0] = address(govOps);
        governors[1] = address(govRes);
        executor = new GovernorExecutor(admin, 2 days, governors);
        guard = new GovernorGuard(admin, address(govOps));

        transactions = new Transaction(
            opWallet,
            10000e6,
            5000e18,
            address(executor),
            admin,
            address(usdc),
            address(sci)
        );

        sci.approve(address(govOps), 100000000000000e18);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(transactions), 100000000000000e18);
        usdc.approve(address(transactions), 100000000000000e6);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(usdc), admin, 100000000e6);
        deal(address(sci), admin, 10000000e18);

        po.setGovOps(address(govOps));
        staking.setGovOps(address(govOps));
        staking.setGovRes(address(govRes));
        govOps.setGovGuard(address(guard));
        // govRes.setGovGuard(address(guard));
        govOps.setGovExec(address(executor));
        staking.setGovExec(address(executor));
        govRes.setGovExec(address(executor));
        vm.stopPrank();

        vm.startPrank(customAddress);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), customAddress, 10000000e18);
        deal(address(usdc), customAddress, 10000000e6);
        vm.stopPrank();

        vm.startPrank(researchFundingWallet);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), researchFundingWallet, 100000000e18);
        deal(address(usdc), researchFundingWallet, 10000000e6);
        vm.stopPrank();

        vm.startPrank(addr1);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), addr1, 200000000e18);
        deal(address(usdc), addr1, 10000e6);
        vm.stopPrank();

        vm.startPrank(addr2);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), addr2, 100000000e18);
        deal(address(usdc), addr2, 100000000e6);
        vm.stopPrank();

        vm.startPrank(addr3);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), addr3, 100000000e18);
        deal(address(usdc), addr3, 100000000e6);
        vm.stopPrank();
    }

    function test_SetParticipationToken() public {
        vm.startPrank(admin);
        govOps.setPoToken(addr5);
        assertEq(addr5, govOps.getPoToken());
        vm.stopPrank();
    }

    function test_CreateProposal() public {
        vm.startPrank(admin);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);

        GovernorOperations.Proposal memory proposal = govOps.getProposalInfo(
            id
        );

        assertEq(proposal.info, "Info");
        assertEq(proposal.startBlockNum, block.number);
        assertEq(
            proposal.endTimestamp,
            block.timestamp + govOps.proposalLifeTime()
        );
        assertEq(
            uint(proposal.status),
            uint(GovernorOperations.ProposalStatus.Active)
        );
        assertEq(proposal.action, address(transactions));
        assertEq(proposal.votesFor, 0);
        assertEq(proposal.votesAgainst, 0);
        assertEq(proposal.totalVotes, 0);
        assertEq(proposal.executable, true);
        assertEq(proposal.quadraticVoting, false);
        vm.stopPrank();
    }

    function test_AddDelegate() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        addDelegate = new AddDelegate(
            addr1,
            address(executor),
            address(staking)
        );
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(addDelegate), false);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();
    }

    function test_ChangeGovernanceParametersGovOps() public {
        vm.startPrank(admin);
        //no need to add as executor as done automatically
        govParams = new GovernorParameters(
            address(govOps),
            address(executor),
            "quorum",
            (IERC20(sci).totalSupply() / 10000) * 600
        );
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        (, uint256 quorum, , , , , ) = govOps.getGovernanceParameters();
        assertEq(quorum, (IERC20(sci).totalSupply() / 10000) * 300);
        govOps.propose("Info", address(govParams), false);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();
        (, uint256 quorum1, , , , , ) = govOps.getGovernanceParameters();
        assertEq(quorum1, (IERC20(sci).totalSupply() / 10000) * 600);
    }

    function test_ChangeGovernanceParametersGovRes() public {
        vm.startPrank(admin);
        govParamsRes = new GovernorParameters(
            address(govRes),
            address(executor),
            "quorum",
            3
        );
        // address[] memory governors = new address[](1);
        // governors[0] = address(govParamsRes);
        // govRes.addExecutors(governors);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        (, uint256 quorum, , , , , ) = govRes.getGovernanceParameters();
        assertEq(quorum, 1);
        govOps.propose("Info", address(govParamsRes), false);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();
        (, uint256 quorum1, , , , , ) = govRes.getGovernanceParameters();
        assertEq(quorum1, 3);
    }

    function test_ElectScientists() public {
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
        election = new Election(
            electedMembers,
            address(executor),
            address(govRes)
        );
        vm.stopPrank();
        vm.startPrank(admin);
        staking.lock(1000e18);
        // address[] memory governors = new address[](1);
        // governors[0] = address(election);
        // govRes.addExecutors(governors);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(election), false);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();
        assertTrue(govRes.checkDueDiligenceRole(addr1) == true);
    }

    function test_ImpeachScientists() public {
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
        election = new Election(
            electedMembers,
            address(executor),
            address(govRes)
        );
        vm.stopPrank();
        vm.startPrank(admin);
        staking.lock(1000e18);
        // address[] memory governors = new address[](1);
        // governors[0] = address(election);
        // govRes.addExecutors(governors);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(election), false);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();

        vm.startPrank(admin);
        address[] memory impeachedMembers = new address[](2);
        impeachedMembers[0] = addr1;
        impeachedMembers[1] = addr2;
        impeachment = new Impeachment(
            impeachedMembers,
            address(executor),
            address(govRes)
        );
        address[] memory governors2 = new address[](1);
        governors2[0] = address(impeachment);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id2 = govOps.getProposalIndex();
        govOps.propose("Info", address(impeachment), false);
        govOps.voteStandard(id2, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id2);
        vm.warp(block.timestamp + 3 days);
        vm.startPrank(admin);
        // govRes.addExecutors(governors2);
        govOps.execute(id2);
        vm.stopPrank();

        assertTrue(govRes.checkDueDiligenceRole(addr1) == false);
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        govOps.voteStandard(id, true);

        GovernorOperations.Proposal memory proposal = govOps.getProposalInfo(
            id
        );

        assertEq(proposal.votesFor, 2000000e18);
        assertEq(proposal.totalVotes, 2000000e18);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govOps.voteLockTime()));
        vm.stopPrank();
    }

    function test_ChangeVoteFor() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        govOps.voteStandard(id, true);

        GovernorOperations.Proposal memory proposal = govOps.getProposalInfo(
            id
        );

        assertEq(proposal.votesFor, 2000000e18);
        assertEq(proposal.totalVotes, 2000000e18);

        govOps.voteStandard(id, false);
        GovernorOperations.Proposal memory proposal2 = govOps.getProposalInfo(
            id
        );

        assertEq(proposal2.totalVotes - proposal2.votesFor, 2000000e18);
        assertEq(proposal2.totalVotes, 2000000e18);

        vm.stopPrank();
    }

    function test_VoteMultiple() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        vm.warp(8 days);
        uint256 id2 = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        vm.warp(15 days);
        uint256 id3 = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        govOps.voteStandard(id, true);
        govOps.voteStandard(id2, true);
        govOps.voteStandard(id3, true);

        assertEq(po.balanceOf(addr2, 0), 6);
    }

    function test_VoteForProposalWithQuadraticVoting() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transactions), true);
        vm.stopPrank();

        bool isUnique = true;
        // bytes32 messageHash = keccak256(abi.encodePacked(addr1, isUnique));
        bytes32 messageHash = keccak256(abi.encodePacked(addr1, isUnique));
        console2.logBytes32(messageHash);

        vm.startPrank(signer);
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(10, ethSignedMessageHash);

        // Construct the signature from the components
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
        vm.startPrank(addr1);
        bool support = true;

        govOps.voteQV(id, support, isUnique, signature);
        GovernorOperations.Proposal memory proposal = govOps.getProposalInfo(
            id
        );
        assertEq(proposal.votesFor, 1414e18);
        assertEq(proposal.totalVotes, 1414e18);
        assertEq(proposal.quadraticVoting, true);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govOps.voteLockTime()));
        vm.stopPrank();
    }

    function test_SuccessfulVoteChangeWithinWindow() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);

        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);

        govOps.voteStandard(id, true);

        vm.warp(block.timestamp + govOps.voteChangeTime() - 1);

        govOps.voteStandard(id, false);
        GovernorOperations.UserVoteData memory userVoteData = govOps
            .getUserVoteData(addr2, id);
        assertEq(userVoteData.previousSupport, false);

        vm.stopPrank();
    }

    function test_RevertVoteIfVoteChangeCutOffPassed() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        vm.warp(
            block.timestamp +
                govOps.proposalLifeTime() -
                govOps.voteChangeCutOff() +
                1
        );
        govOps.voteStandard(id, true);
        bytes4 selector = bytes4(
            keccak256("VoteChangeNotAllowedAfterCutOff()")
        );
        vm.expectRevert(selector);
        govOps.voteStandard(id, true);
        vm.stopPrank();
    }

    function test_RevertVoteIfVoteChangeWindowExpired() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);

        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);

        govOps.voteStandard(id, true);

        vm.warp(block.timestamp + govOps.voteChangeTime() + 1);

        bytes4 selector = bytes4(keccak256("VoteChangeWindowExpired()"));
        vm.expectRevert(selector);

        govOps.voteStandard(id, false);

        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {
        vm.startPrank(addr1);
        staking.lock(1.8e23);

        govOps.propose("Info", address(transactions), false);
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        govOps.voteStandard(1, true);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        uint256 proposalLifeTime = govOps.proposalLifeTime();
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
        govOps.schedule(id);
        vm.stopPrank();
    }

    function test_ScheduleProposal() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        govOps.schedule(id);
        GovernorOperations.Proposal memory proposal = govOps.getProposalInfo(
            id
        );
        assertTrue(
            proposal.status == GovernorOperations.ProposalStatus.Scheduled
        );
        vm.stopPrank();
    }

    function test_RevertFinalizationIfQuorumNotReached() public {
        vm.startPrank(addr1);
        staking.lock(20000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(5000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        uint256 quorum = govOps.quorum();
        bytes4 selector = bytes4(
            keccak256("QuorumNotReached(uint256,uint256,uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, id, 5000e18, quorum));

        govOps.schedule(id);
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsFinalized() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.warp(4.1 weeks);
        govOps.schedule(id);
        vm.stopPrank();
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1));
        govOps.voteStandard(id, true);
        vm.stopPrank();
    }

    function test_RevertFreeTokensWhenVotesLocked() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        bytes4 selector = bytes4(
            keccak256("TokensStillLocked(uint256,uint256)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(selector, voteLockEnd, block.timestamp)
        );
        vm.startPrank(addr2);
        staking.free(2000e18);
        vm.stopPrank();
    }

    function test_FreeTokensAterVotingAndAfterVoteLockEndPassed() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transactions), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        govOps.voteStandard(id, true);
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        vm.warp(voteLockEnd);
        staking.free(2000e18);
        vm.stopPrank();
    }

    function test_ExecuteTransactionProposal() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transactions), false);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.schedule(id);
        vm.warp(4.1 weeks + 3 days);
        govOps.execute(id);
        assertEq(sci.balanceOf(opWallet), 5000e18);
        assertEq(usdc.balanceOf(opWallet), 10000e6);
        vm.stopPrank();
    }

    function test_RevertExecutionFunctionIfIncorrectPhase() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transactions), false);
        govOps.voteStandard(id, true);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(
            abi.encodeWithSelector(
                selector,
                GovernorOperations.ProposalStatus.Active
            )
        );
        govOps.execute(id);
        vm.stopPrank();
    }

    function test_CancelRejectedProposal() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transactions), false);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        govOps.voteStandard(id, false);
        vm.warp(4.1 weeks);
        govOps.cancelRejected(id);
        GovernorOperations.Proposal memory proposal = govOps.getProposalInfo(
            id
        );
        assertTrue(
            proposal.status == GovernorOperations.ProposalStatus.Cancelled
        );
        vm.stopPrank();
    }

    function test_CancelMaliciousProposal() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transactions), false);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        vm.stopPrank();
        govOps.schedule(id);
        vm.startPrank(admin);
        guard.cancel(id);
        GovernorOperations.Proposal memory proposal = govOps.getProposalInfo(
            id
        );
        assertTrue(
            proposal.status == GovernorOperations.ProposalStatus.Cancelled
        );
        vm.stopPrank();
    }

    // function test_CancelOperationsProposalWithQV() public {
    //     vm.startPrank(addr2);
    //     staking.lock(2000000e18);
    //     uint256 id = govOps.getProposalIndex();
    //     govOps.propose("Info", address(transactions), true);
    //     vm.stopPrank();
    //     vm.warp(4.1 weeks);
    //     vm.startPrank(addr3);
    //     guard.cancel(id);
    //     GovernorOperations.Proposal memory proposal = govOps.getProposalInfo(
    //         id
    //     );
    //     assertTrue(
    //         proposal.status == GovernorOperations.ProposalStatus.Cancelled
    //     );
    //     vm.stopPrank();
    // }

    function test_EmitCancelledEventRejected() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transactions), false);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        vm.stopPrank();
        vm.startPrank(admin);
        govOps.schedule(id);
        vm.expectEmit(true, true, false, true);
        emit Cancelled(id, false);
        guard.cancel(id);
        vm.stopPrank();
    }

    function test_EmitCancelledEventMalicious() public {
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transactions), false);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        vm.stopPrank();
        vm.startPrank(admin);
        govOps.schedule(id);
        vm.expectEmit(true, true, false, true);
        emit Cancelled(id, false);
        guard.cancel(id);
        vm.stopPrank();
    }

    function test_CompleteProposal() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(0), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.schedule(id);

        govOps.complete(id);
        GovernorOperations.Proposal memory proposal = govOps.getProposalInfo(
            id
        );
        assertTrue(
            proposal.status == GovernorOperations.ProposalStatus.Completed
        );
        vm.stopPrank();
    }

    function test_RevertProposalIfInfoEmpty() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        bytes4 selector = bytes4(keccak256("InvalidInput()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("", address(transactions), false);
        vm.stopPrank();
    }

    function test_RevertIfProposeLock() public {
        vm.startPrank(addr1);
        staking.lock(2000000e18);
        govOps.propose("Info", address(transactions), false);

        bytes4 selector = bytes4(keccak256("ProposeLock()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("Info", address(transactions), false);

        vm.stopPrank();
    }
}
