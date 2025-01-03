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
import "contracts/executors/AddDelegate.sol";
import "forge-std/console2.sol";
import "contracts/DeployedAddresses.sol";

contract GovernorOperationsTest is Test {
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
    Impeachment impeachment;
    ParameterChange govParams;
    ParameterChange govParamsRes;
    AddDelegate addDelegate;
    // address signer = 0x690BF2dB31D39EE0a88fcaC89117b66a588E865a;
    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address delegator = 0x690BF2dB31D39EE0a88fcaC89117b66a588E865a;
    address delegatee = 0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe;
    address researchFundingWallet = vm.addr(6);
    address admin = DeployedAddresses.admin;
    address opWallet = vm.addr(8);

    event StatusUpdated(
        uint256 indexed id,
        GovernorOperations.ProposalStatus indexed status
    );

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

        transaction = new Transaction(
            admin,
            opWallet,
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
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(sciManager), 1000000000000e18);
        deal(address(sci), researchFundingWallet, 100000000e18);
        deal(address(usdc), researchFundingWallet, 10000000e6);
        vm.stopPrank();

        vm.startPrank(addr1);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(sciManager), 1000000000000e18);
        deal(address(sci), addr1, 200000000e18);
        deal(address(usdc), addr1, 10000e6);
        vm.stopPrank();

        vm.startPrank(addr2);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(sciManager), 1000000000000e18);
        deal(address(sci), addr2, 100000000e18);
        deal(address(usdc), addr2, 100000000e6);
        vm.stopPrank();

        vm.startPrank(addr3);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(sciManager), 1000000000000e18);
        deal(address(sci), addr3, 100000000e18);
        deal(address(usdc), addr3, 100000000e6);
        vm.stopPrank();

        vm.startPrank(delegatee);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(sciManager), 1000000000000e18);
        deal(address(sci), delegatee, 100000000e18);
        deal(address(usdc), delegatee, 100000000e6);
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
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);

        GovernorOperations.Proposal memory proposal = govOps.getProposal(id);

        assertEq(proposal.info, "Info");
        assertEq(proposal.startBlockNum, block.number);
        assertEq(
            proposal.endTimestamp,
            block.timestamp + govOps.getGovernanceParameters().proposalLifetime
        );
        assertEq(
            uint(proposal.status),
            uint(GovernorOperations.ProposalStatus.Active)
        );
        assertEq(proposal.action, address(transaction));
        assertEq(proposal.votesFor, 0);
        assertEq(proposal.votesAgainst, 0);
        assertEq(proposal.votesTotal, 0);
        assertEq(proposal.executable, true);
        assertEq(proposal.quadraticVoting, false);
        vm.stopPrank();
    }

    function test_AddDelegate() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        addDelegate = new AddDelegate(
            addr1,
            address(executor),
            address(sciManager)
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
        govParams = new ParameterChange(
            address(govOps),
            address(executor),
            "quorum",
            (IERC20(sci).totalSupply() / 10000) * 600
        );
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        assertEq(
            govOps.getGovernanceParameters().quorum,
            (IERC20(sci).totalSupply() / 10000) * 300
        );
        govOps.propose("Info", address(govParams), false);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();
        assertEq(
            govOps.getGovernanceParameters().quorum,
            (IERC20(sci).totalSupply() / 10000) * 600
        );
    }

    function test_ChangeGovernanceParametersGovRes() public {
        vm.startPrank(admin);
        govParamsRes = new ParameterChange(
            address(govRes),
            address(executor),
            "quorum",
            3
        );
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        assertEq(govRes.getGovernanceParameters().quorum, 1);
        govOps.propose("Info", address(govParamsRes), false);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();
        assertEq(govRes.getGovernanceParameters().quorum, 3);
    }

    function test_ElectScientists() public {
        vm.startPrank(delegatee);
        sciManager.lock(1000e18);
        vm.stopPrank();
        vm.startPrank(addr1);
        address[] memory electedMembers = new address[](1);
        electedMembers[0] = delegatee;
        election = new Election(
            electedMembers,
            address(govRes),
            address(executor)
        );
        vm.stopPrank();
        vm.startPrank(admin);
        sciManager.lock(1000e18);
        // address[] memory governors = new address[](1);
        // governors[0] = address(election);
        // govRes.addExecutors(governors);
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
        assertTrue(govRes.checkDueDiligenceRole(delegatee) == true);
        assertTrue(
            govRes.checkDueDiligenceRole(
                0x690BF2dB31D39EE0a88fcaC89117b66a588E865a
            ) == true
        );
    }

    function test_ImpeachScientists() public {
        // vm.startPrank(researchFundingWallet);
        // sciManager.lock(1000e18);
        // vm.stopPrank();
        // vm.startPrank(addr2);
        // sciManager.lock(1000e18);
        // vm.stopPrank();
        // vm.startPrank(addr1);
        // address[] memory electedMembers = new address[](4);
        // electedMembers[0] = delegatee;
        // electedMembers[1] = 0x690BF2dB31D39EE0a88fcaC89117b66a588E865a;
        // election = new Election(
        //     electedMembers,
        //     address(govRes),
        //     address(executor)
        // );
        // vm.stopPrank();
        vm.startPrank(admin);
        sciManager.lock(1000e18);
        // address[] memory governors = new address[](1);
        // governors[0] = address(election);
        // govRes.addExecutors(governors);
        // vm.stopPrank();
        // vm.startPrank(addr1);
        // sciManager.lock(2000000e18);
        // uint256 id = govOps.getProposalIndex();
        // govOps.propose("Info", address(election), false);
        // govOps.voteStandard(id, true);
        // vm.warp(block.timestamp + 4.1 weeks);
        // govOps.schedule(id);
        // vm.warp(block.timestamp + 3 days);
        // govOps.execute(id);
        // vm.stopPrank();
        assertTrue(
            govRes.checkDueDiligenceRole(
                0x690BF2dB31D39EE0a88fcaC89117b66a588E865a
            ) == true
        );

        vm.startPrank(admin);
        address[] memory impeachedMembers = new address[](1);
        impeachedMembers[0] = 0x690BF2dB31D39EE0a88fcaC89117b66a588E865a;
        impeachment = new Impeachment(
            impeachedMembers,
            address(govRes),
            address(executor)
        );
        address[] memory governors2 = new address[](1);
        governors2[0] = address(impeachment);
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
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

        assertTrue(govRes.checkDueDiligenceRole(delegatee) == false);
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);
        govOps.voteStandard(id, true);

        GovernorOperations.Proposal memory proposal = govOps.getProposal(id);

        assertEq(proposal.votesFor, 2000000e18);
        assertEq(proposal.votesTotal, 2000000e18);

        (, , , uint256 voteLockEnd, , , , , ) = sciManager.users(addr1);

        assertEq(
            voteLockEnd,
            (block.timestamp + govOps.getGovernanceParameters().voteLockTime)
        );
        vm.stopPrank();
    }

    function test_ChangeVoteFor() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);
        govOps.voteStandard(id, true);

        GovernorOperations.Proposal memory proposal = govOps.getProposal(id);

        assertEq(proposal.votesFor, 2000000e18);
        assertEq(proposal.votesTotal, 2000000e18);

        govOps.voteStandard(id, false);
        GovernorOperations.Proposal memory proposal2 = govOps.getProposal(id);

        assertEq(proposal2.votesTotal - proposal2.votesFor, 2000000e18);
        assertEq(proposal2.votesTotal, 2000000e18);

        vm.stopPrank();
    }

    function test_VoteMultiple() public {
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(addr1);
        uint256 id2 = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        govOps.voteStandard(id2, true);
        vm.stopPrank();

        vm.startPrank(addr1);
        vm.warp(block.timestamp + 15 days);
        uint256 id3 = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();

        vm.startPrank(addr2);
        govOps.voteStandard(id3, true);
        govOps.claimPo();
        vm.stopPrank();
        assertEq(po.balanceOf(addr2, 0), 6);
    }

    function test_VoteForProposalWithQuadraticVoting() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), true);
        vm.stopPrank();

        bool isUnique = true;
        // bytes32 messageHash = keccak256(abi.encodePacked(addr1, isUnique));
        bytes32 messageHash = keccak256(abi.encodePacked(addr1, isUnique));
        console2.logBytes32(messageHash);
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            ethSignedMessageHash
        );

        // Construct the signature from the components
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
        vm.startPrank(addr1);
        bool support = true;

        govOps.voteQV(id, support, isUnique, signature);
        GovernorOperations.Proposal memory proposal = govOps.getProposal(id);
        assertEq(proposal.votesFor, 1414e18);
        assertEq(proposal.votesTotal, 1414e18);
        assertEq(proposal.quadraticVoting, true);

        (, , , uint256 voteLockEnd, , , , , ) = sciManager.users(addr1);

        assertEq(
            voteLockEnd,
            (block.timestamp + govOps.getGovernanceParameters().voteLockTime)
        );
        vm.stopPrank();
    }

    function test_SuccessfulVoteChangeWithinWindow() public {
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);

        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);

        govOps.voteStandard(id, true);

        vm.warp(
            block.timestamp +
                govOps.getGovernanceParameters().voteChangeTime -
                1
        );

        govOps.voteStandard(id, false);
        GovernorOperations.UserVoteData memory userVoteData = govOps
            .getUserVoteData(addr2, id);
        assertEq(userVoteData.previousSupport, false);

        vm.stopPrank();
    }

    function test_RevertIfPreviousDelegateeHasAlreadyVoted() public {
        vm.startPrank(delegator);
        addDelegate = new AddDelegate(
            delegatee,
            address(executor),
            address(sciManager)
        );
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(addDelegate), false);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        vm.stopPrank();

        vm.startPrank(delegator);
        sciManager.delegate(delegatee);
        vm.stopPrank();
        vm.warp(block.timestamp + 31 days);
        vm.startPrank(delegatee);
        uint256 id2 = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        govOps.voteStandard(id2, true);
        vm.stopPrank();

        vm.startPrank(delegator);
        sciManager.delegate(address(0));
        vm.stopPrank();

        vm.startPrank(delegator);
        bytes4 selector = bytes4(
            keccak256("DelegateeHasAlreadyVoted(uint256,address)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, id2, delegatee));
        govOps.voteStandard(id2, true);
        vm.stopPrank();
    }

    function test_RevertVoteIfVoteChangeCutOffPassed() public {
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);
        vm.warp(
            block.timestamp +
                govOps.getGovernanceParameters().proposalLifetime -
                govOps.getGovernanceParameters().voteChangeCutOff +
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
        sciManager.lock(2000000e18);

        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);

        govOps.voteStandard(id, true);

        vm.warp(
            block.timestamp +
                govOps.getGovernanceParameters().voteChangeTime +
                1
        );

        bytes4 selector = bytes4(keccak256("VoteChangeWindowExpired()"));
        vm.expectRevert(selector);

        govOps.voteStandard(id, false);

        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {
        vm.startPrank(addr1);
        sciManager.lock(1.8e23);

        govOps.propose("Info", address(transaction), false);
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        govOps.voteStandard(12, true);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);
        uint256 proposalLifetime = govOps
            .getGovernanceParameters()
            .proposalLifetime;
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
        govOps.schedule(id);
        vm.stopPrank();
    }

    function test_ScheduleProposal() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id);
        GovernorOperations.Proposal memory proposal = govOps.getProposal(id);
        assertTrue(
            proposal.status == GovernorOperations.ProposalStatus.Scheduled
        );
        vm.stopPrank();
    }

    function test_RevertFinalizationIfQuorumNotReached() public {
        vm.startPrank(addr1);
        sciManager.lock(20000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        sciManager.lock(5000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(block.timestamp + 4.1 weeks);
        uint256 quorum = govOps.getGovernanceParameters().quorum;
        bytes4 selector = bytes4(
            keccak256("QuorumNotReached(uint256,uint256,uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, id, 5000e18, quorum));

        govOps.schedule(id);
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsFinalized() public {
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.warp(block.timestamp + 4.1 weeks);
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
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        govOps.voteStandard(id, true);
        (, , , uint256 voteLockEnd, , , , , ) = sciManager.users(addr2);
        bytes4 selector = bytes4(
            keccak256("TokensStillLocked(uint256,uint256)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(selector, voteLockEnd, block.timestamp)
        );
        sciManager.free(2000e18); //only passes if voteLockTime is not zero.
        vm.stopPrank();
    }

    function test_FreeTokensAterVotingAndAfterVoteLockEndPassed() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();

        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        govOps.voteStandard(id, true);
        (, , , uint256 voteLockEnd, , , , , ) = sciManager.users(addr2);
        vm.warp(voteLockEnd);
        sciManager.free(2000e18);
        vm.stopPrank();
    }

    function test_ExecuteTransactionProposal() public {
        // vm.startPrank(admin);
        // usdc.approve(address(transaction), 100000000000000e6);
        // sci.approve(address(transaction), 100000000000000e18);
        // vm.stopPrank();

        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id);
        vm.warp(block.timestamp + 3 days);
        govOps.execute(id);
        assertEq(sci.balanceOf(opWallet), 5000e18);
        assertEq(usdc.balanceOf(opWallet), 10000e6);
        vm.stopPrank();
    }

    function test_RevertExecutionFunctionIfIncorrectPhase() public {
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
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
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        govOps.voteStandard(id, false);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.cancelRejected(id);
        GovernorOperations.Proposal memory proposal = govOps.getProposal(id);
        assertTrue(
            proposal.status == GovernorOperations.ProposalStatus.Canceled
        );
        vm.stopPrank();
    }

    function test_CancelMaliciousProposal() public {
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        vm.stopPrank();
        govOps.schedule(id);
        vm.startPrank(admin);
        guard.cancelOps(id);
        GovernorOperations.Proposal memory proposal = govOps.getProposal(id);
        assertTrue(
            proposal.status == GovernorOperations.ProposalStatus.Canceled
        );
        vm.stopPrank();
    }

    function test_EmitCanceledEventRejected() public {
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        vm.stopPrank();
        vm.startPrank(admin);
        govOps.schedule(id);
        vm.expectEmit(true, true, false, true);
        emit StatusUpdated(id, GovernorOperations.ProposalStatus.Canceled);
        guard.cancelOps(id);
        vm.stopPrank();
    }

    function test_EmitCanceledEventMalicious() public {
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(transaction), false);
        vm.stopPrank();
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        vm.stopPrank();
        vm.startPrank(admin);
        govOps.schedule(id);
        vm.expectEmit(true, true, false, true);
        emit StatusUpdated(id, GovernorOperations.ProposalStatus.Canceled);
        guard.cancelOps(id);
        vm.stopPrank();
    }

    function test_CompleteProposal() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(0), false);
        vm.stopPrank();
        vm.startPrank(addr2);
        sciManager.lock(2000000e18);
        govOps.voteStandard(id, true);
        vm.warp(block.timestamp + 4.1 weeks);
        govOps.schedule(id);

        govOps.complete(id);
        GovernorOperations.Proposal memory proposal = govOps.getProposal(id);
        assertTrue(
            proposal.status == GovernorOperations.ProposalStatus.Completed
        );
        vm.stopPrank();
    }

    function test_RevertProposalIfInfoEmpty() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        bytes4 selector = bytes4(keccak256("InvalidInput()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("", address(transaction), false);
        vm.stopPrank();
    }

    function test_RevertIfProposeLock() public {
        vm.startPrank(addr1);
        sciManager.lock(2000000e18);
        govOps.propose("Info", address(transaction), false);

        bytes4 selector = bytes4(keccak256("ProposeLock()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("Info", address(transaction), false);

        vm.stopPrank();
    }
}
