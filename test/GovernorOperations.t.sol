// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/tokens/Po.sol";
import "contracts/tokens/Sci.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/staking/Staking.sol";
import "forge-std/console2.sol";

contract GovernorOperationsTest is Test {
    GovernorOperations public govOps;
    GovernorResearch public govRes;
    Po public po;
    Sci public sci;
    MockUsdc public usdc;
    Staking public staking;
    address signer = vm.addr(10);
    address customAddress = signer;
    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address donationWallet = vm.addr(6);
    address treasuryWallet = vm.addr(7);
    address royaltyAddress = vm.addr(8);
    address opWallet = vm.addr(9);
    bytes32 govIdCircuitId =
        0x729d660e1c02e4e419745e617d643f897a538673ccf1051e093bbfa58b0a120b;
    bytes32 phoneCircuitId =
        0xbce052cf723dca06a21bd3cf838bc518931730fb3db7859fc9cc86f0d5483495;
    // address customAddress = 0x690BF2dB31D39EE0a88fcaC89117b66a588E865a;
    bytes32 public constant DUE_DILIGENCE_ROLE =
        keccak256("DUE_DILIGENCE_ROLE");

    event Cancelled(uint256 indexed id);

    function setUp() public {
        usdc = new MockUsdc(10000000e18);

        vm.startPrank(treasuryWallet);
        sci = new Sci(treasuryWallet, 4538400);
        po = new Po("", treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        govRes = new GovernorResearch(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        govOps = new GovernorOperations(
            address(govRes),
            address(staking),
            treasuryWallet,
            address(usdc),
            address(sci),
            address(po),
            signer
        );
        po.setGovOps(address(govOps));
        staking.setGovOps(address(govOps));
        staking.setGovRes(address(govRes));
        govRes.setGovOps(address(govOps));
        govOps.setGovParams("proposalLifeTime", 4 weeks);
        govOps.setGovParams("quorum", 6000e18);
        govOps.setGovParams("voteLockTime", 1 weeks);
        govOps.setGovParams("proposeLockTime", 1 weeks);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(usdc), treasuryWallet, 100000000e6);
        deal(address(sci), treasuryWallet, 10000000e18);
        deal(treasuryWallet, 10000 ether);
        vm.stopPrank();

        vm.startPrank(customAddress);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), customAddress, 10000e18);
        deal(address(usdc), customAddress, 10000e6);
        deal(addr1, 10000 ether);
        vm.stopPrank();

        vm.startPrank(donationWallet);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), donationWallet, 10000e18);
        deal(address(usdc), donationWallet, 10000000e6);
        deal(donationWallet, 5000 ether);
        vm.stopPrank();

        vm.startPrank(addr1);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), addr1, 200000000e18);
        deal(address(usdc), addr1, 10000e6);
        deal(addr1, 10000 ether);
        vm.stopPrank();

        vm.startPrank(addr2);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), addr2, 10000e18);
        deal(address(usdc), addr2, 10000e6);
        deal(addr2, 10000 ether);
        vm.stopPrank();

        vm.startPrank(addr3);
        sci.approve(address(govOps), 1000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), addr3, 10000e18);
        deal(address(usdc), addr3, 10000e6);
        deal(addr3, 10000 ether);
        vm.stopPrank();
    }

    function test_SetGovParams() public {
        assertEq(govOps.proposalLifeTime(), 4 weeks);
        assertEq(govOps.quorum(), 6000e18);
        assertEq(govOps.voteLockTime(), 1 weeks);
        assertEq(govOps.proposeLockTime(), 1 weeks);
    }

    function test_SetParticipationToken() public {
        vm.startPrank(treasuryWallet);
        govOps.setPoToken(addr5);
        assertEq(addr5, govOps.getPoToken());
        vm.stopPrank();
    }

    function test_OperationsProposalUsingUsdc() public {
        vm.startPrank(treasuryWallet);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );

        (
            uint256 startBlockNum,
            uint256 endTimeStamp,
            GovernorOperations.ProposalStatus status,
            GovernorOperations.ProjectInfo memory details,
            uint256 votesFor,
            uint256 totalVotes,
            bool quadraticVoting
        ) = govOps.getProposalInfo(id);

        assertEq(startBlockNum, block.number);
        assertEq(endTimeStamp, block.timestamp + govOps.proposalLifeTime());
        assertTrue(status == GovernorOperations.ProposalStatus.Active);
        assertEq(votesFor, 0);
        assertEq(totalVotes, 0);
        assertEq(quadraticVoting, false);
        assertEq(details.info, "Info");
        assertEq(details.targetWallet, opWallet);
        assertTrue(details.payment == GovernorOperations.Payment.Usdc);
        assertEq(details.amount, 5000000e6);
        assertEq(details.amountSci, 0);
        assertTrue(
            details.proposalType == GovernorOperations.ProposalType.Transaction
        );
        vm.stopPrank();
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        govOps.voteStandard(id, true);

        (, , , , uint256 votesFor, uint256 totalVotes, ) = govOps
            .getProposalInfo(id);

        assertEq(votesFor, 10000e18);
        assertEq(totalVotes, 10000e18);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govOps.voteLockTime()));
        vm.stopPrank();
    }

    function test_ChangeVoteFor() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        govOps.voteStandard(id, true);

        (, , , , uint256 votesFor, uint256 totalVotes, ) = govOps
            .getProposalInfo(id);

        assertEq(votesFor, 10000e18);
        assertEq(totalVotes, 10000e18);

        govOps.voteStandard(id, false);
        (, , , , uint256 votesFor1, uint256 totalVotes1, ) = govOps
            .getProposalInfo(id);

        assertEq(totalVotes1 - votesFor1, 10000e18);
        assertEq(totalVotes1, 10000e18);

        vm.stopPrank();
    }

    function test_VoteMultiple() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.warp(8 days);
        uint256 id2 = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.warp(15 days);
        uint256 id3 = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(10000e18);
        govOps.voteStandard(id, true);
        govOps.voteStandard(id2, true);
        govOps.voteStandard(id3, true);

        assertEq(po.balanceOf(addr2, 0), 6);
    }

    function test_VoteForProposalWithQuadraticVoting() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            true
        );
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
        // Call the voteQV function with the signature
        bool support = true;

        govOps.voteQV(id, support, isUnique, signature);

        (
            ,
            ,
            ,
            ,
            uint256 votesFor,
            uint256 totalVotes,
            bool quadraticVoting
        ) = govOps.getProposalInfo(id);

        assertEq(votesFor, 100e18);
        assertEq(totalVotes, 100e18);
        assertEq(quadraticVoting, true);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govOps.voteLockTime()));
        vm.stopPrank();
    }

function test_SuccessfulVoteChangeWithinWindow() public {
    vm.startPrank(addr2);
    staking.lock(10000e18);
    
    uint256 id = govOps.getProposalIndex();
    govOps.propose(
        "Info",
        opWallet,
        5000000e6,
        0,
        0,
        GovernorOperations.ProposalType.Transaction,
        false
    );

    govOps.voteStandard(id, true);

    vm.warp(block.timestamp + govOps.voteChangeTime() - 1);

    govOps.voteStandard(id, false);

    (, , bool previousSupport,) = govOps.getUserVoteData(addr2, id);
    assertEq(previousSupport, false);

    vm.stopPrank();
}


    function test_RevertVoteIfVoteChangeCutOffPassed() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.warp(block.timestamp + govOps.proposalLifeTime() - govOps.voteChangeCutOff() + 1);
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
        staking.lock(10000e18);

        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );

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
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        govOps.voteStandard(1, true);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
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
        govOps.finalize(id);
        vm.stopPrank();
    }

    function test_FinalizeVotingOperationsProposal() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(10000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        (, , GovernorOperations.ProposalStatus status, , , , ) = govOps
            .getProposalInfo(id);
        assertTrue(status == GovernorOperations.ProposalStatus.Scheduled);
        vm.stopPrank();
    }

    function test_RevertFinalizationIfQuorumNotReached() public {
        vm.startPrank(addr1);
        staking.lock(100000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
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

        govOps.finalize(id);
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsFinalized() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1));
        govOps.voteStandard(id, true);
        vm.stopPrank();
    }

    function test_RevertFreeTokensWhenVotesLocked() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(10000e18);
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
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(10000e18);
        govOps.voteStandard(id, true);
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        vm.warp(voteLockEnd);
        staking.free(2000e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingUsdc() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        govOps.voteStandard(id, true);
        vm.stopPrank();

        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        (, , , GovernorOperations.ProjectInfo memory details, , , ) = govOps
            .getProposalInfo(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute(id);
        (, , GovernorOperations.ProposalStatus status, , , , ) = govOps
            .getProposalInfo(id);

        assertTrue(status == GovernorOperations.ProposalStatus.Executed);
        assertEq(usdc.balanceOf(details.targetWallet), details.amount);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingSci() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            0,
            0,
            1000e18,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute(id);
        (, , , GovernorOperations.ProjectInfo memory details, , , ) = govOps
            .getProposalInfo(id);

        assertEq(sci.balanceOf(details.targetWallet), 1000e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalForElection() public {
        vm.startPrank(addr3);
        staking.lock(10000e18);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            addr3,
            0,
            0,
            0,
            GovernorOperations.ProposalType.Election,
            false
        );
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute(id);
        assertEq(govRes.hasRole(DUE_DILIGENCE_ROLE, addr3), true);
        vm.stopPrank();
    }

    function test_ExecuteProposalForImpeachment() public {
        vm.startPrank(addr3);
        staking.lock(10000e18);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            addr3,
            0,
            0,
            0,
            GovernorOperations.ProposalType.Election,
            false
        );
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute(id);
        assertEq(govRes.hasRole(DUE_DILIGENCE_ROLE, addr3), true);
        // vm.warp(1 weeks);
        vm.stopPrank();
        vm.startPrank(addr2);
        uint256 id2 = govOps.getProposalIndex();

        govOps.propose(
            "Info",
            addr3,
            0,
            0,
            0,
            GovernorOperations.ProposalType.Impeachment,
            false
        );
        govOps.voteStandard(id2, true);
        vm.warp(8.1 weeks);
        govOps.finalize(id2);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute(id2);
        assertEq(govRes.hasRole(DUE_DILIGENCE_ROLE, addr3), false);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingSciAndUsdc() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            5000e6,
            0,
            1000e18,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute(id);

        (, , , GovernorOperations.ProjectInfo memory details, , , ) = govOps
            .getProposalInfo(id);

        assertEq(sci.balanceOf(details.targetWallet), 1000e18);
        assertEq(usdc.balanceOf(details.targetWallet), 5000e6);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingCoin() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            0,
            1 ether,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute{value: 1 ether}(id);

        (, , , GovernorOperations.ProjectInfo memory details, , , ) = govOps
            .getProposalInfo(id);

        assertEq(details.targetWallet.balance, 1 ether);
        vm.stopPrank();
    }

    function test_RevertProposalIfInvalidInputForExecutable() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        bytes4 selector = bytes4(
            keccak256("InvalidInputForTransactionExecutable()")
        );
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose(
            "Info",
            opWallet,
            5000e6,
            500 ether,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
    }

    function test_RevertExecutionIfIncorrectMsgValue() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            0,
            500 ether,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        govOps.voteStandard(id, true);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        bytes4 selector = bytes4(keccak256("IncorrectCoinValue()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.execute{value: 501 ether}(id);
        vm.stopPrank();
    }

    function test_RevertExecutionFunctionIfIncorrectPhase() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            0,
            500 ether,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        govOps.voteStandard(id, true);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(
            abi.encodeWithSelector(
                selector,
                GovernorOperations.ProposalStatus.Active
            )
        );
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute{value: 500 ether}(id);
        vm.expectRevert(
            abi.encodeWithSelector(
                selector,
                GovernorOperations.ProposalStatus.Active
            )
        );
        govOps.execute{value: 500 ether}(id);
        vm.stopPrank();
    }

    function test_CancelOperationsProposalWithoutQV() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            0,
            500 ether,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(10000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.warp(4.1 weeks);
        vm.startPrank(addr3);
        govOps.cancel(id);
        (, , GovernorOperations.ProposalStatus status, , , , ) = govOps
            .getProposalInfo(id);
        assertTrue(status == GovernorOperations.ProposalStatus.Cancelled);
        vm.stopPrank();
    }

    function test_CancelOperationsProposalWithQV() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            0,
            500 ether,
            0,
            GovernorOperations.ProposalType.Transaction,
            true
        );
        vm.stopPrank();
        vm.warp(4.1 weeks);
        vm.startPrank(addr3);
        govOps.cancel(id);
        (, , GovernorOperations.ProposalStatus status, , , , ) = govOps
            .getProposalInfo(id);
        assertTrue(status == GovernorOperations.ProposalStatus.Cancelled);
        vm.stopPrank();
    }

    function test_RevertCancelIfProposalOngoing() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            0,
            500 ether,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(100000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.startPrank(addr3);
        (, uint256 endTimestamp, , , , , ) = govOps.getProposalInfo(id);
        bytes4 selector = bytes4(
            keccak256("ProposalOngoing(uint256,uint256,uint256)")
        );
        vm.expectRevert(
            abi.encodeWithSelector(selector, id, block.number, endTimestamp)
        );
        govOps.cancel(id);
        vm.stopPrank();
    }

    function test_EmitCancelledEvent() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            opWallet,
            0,
            500 ether,
            0,
            GovernorOperations.ProposalType.Transaction,
            true
        );
        vm.stopPrank();
        vm.warp(4.1 weeks);
        vm.startPrank(addr3);
        vm.expectEmit(true, true, true, true);
        emit Cancelled(id);
        govOps.cancel(id);
        vm.stopPrank();
    }

    function test_CompleteProposalIfNotExecutable() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            address(0),
            0,
            0,
            0,
            GovernorOperations.ProposalType.Other,
            false
        );
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(10000e18);
        govOps.voteStandard(id, true);
        vm.stopPrank();
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.startPrank(treasuryWallet);
        govOps.complete(id);
        (, , GovernorOperations.ProposalStatus status, , , , ) = govOps
            .getProposalInfo(id);
        assertTrue(status == GovernorOperations.ProposalStatus.Completed);
        vm.stopPrank();
    }

    function test_RevertProposalIfInfoEmpty() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        bytes4 selector = bytes4(keccak256("InvalidInfo()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose(
            "",
            opWallet,
            500000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
    }

    function test_RevertNonExecutableProposalIfPaymentProvided() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        bytes4 selector = bytes4(keccak256("InvalidInputForNonExecutable()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose(
            "Info",
            opWallet,
            500000e6,
            0,
            0,
            GovernorOperations.ProposalType.Other,
            false
        );
        vm.stopPrank();
    }

    function test_RevertIfProposeLock() public {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        govOps.propose(
            "Info",
            address(0),
            0,
            0,
            0,
            GovernorOperations.ProposalType.Other,
            false
        );
        bytes4 selector = bytes4(keccak256("ProposeLock()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose(
            "Info",
            opWallet,
            50000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
    }

    function test_RevertExecutableProposalIfNoPaymentAndWalletProvided()
        public
    {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        bytes4 selector = bytes4(
            keccak256("InvalidInputForTransactionExecutable()")
        );
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose(
            "Info",
            address(0),
            0,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
    }

    function test_RevertExecutableProposalIfNoPaymentButWalletProvided()
        public
    {
        vm.startPrank(addr1);
        staking.lock(10000e18);
        bytes4 selector = bytes4(
            keccak256("InvalidInputForTransactionExecutable()")
        );
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose(
            "Info",
            opWallet,
            0,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
    }

    function test_GovOpsDoesNotWorkAfterTermination() public {
        vm.startPrank(treasuryWallet);
        staking.burnForTermination(4727500e18);
        staking.terminate();
        vm.stopPrank();
        assertEq(govOps.terminated(), true);
        vm.startPrank(addr1);
        bytes4 selector1 = bytes4(keccak256("ContractTerminated(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector1, block.number));
        govOps.propose(
            "Info",
            opWallet,
            500000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
    }

    function test_CancelProposalsIfStillOngoingAfterTermination() public {
        vm.startPrank(treasuryWallet);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            address(0),
            0,
            0,
            0,
            GovernorOperations.ProposalType.Other,
            false
        );
        staking.burnForTermination(4727500e18);
        staking.terminate();
        vm.stopPrank();
        vm.startPrank(addr1);
        govOps.cancel(id);
        vm.stopPrank();
        (, , GovernorOperations.ProposalStatus status, , , , ) = govOps
            .getProposalInfo(id);
        assertTrue(status == GovernorOperations.ProposalStatus.Cancelled);
        assertEq(govOps.terminated(), true);
        vm.startPrank(addr1);
        bytes4 selector1 = bytes4(keccak256("ContractTerminated(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector1, block.number));
        govOps.propose(
            "Info",
            opWallet,
            500000e6,
            0,
            0,
            GovernorOperations.ProposalType.Transaction,
            false
        );
        vm.stopPrank();
    }
}
