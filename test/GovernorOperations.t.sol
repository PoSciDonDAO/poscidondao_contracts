// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/governance/GovernorResearch.sol";
import "contracts/tokens/Participation.sol";
import "contracts/tokens/Sci.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/staking/Staking.sol";
import "forge-std/console2.sol";

contract GovernorOperationsTest is Test {
    GovernorOperations public govOps;
    GovernorResearch public govRes;
    Participation public po;
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

    event Cancelled(uint256 indexed id);

    function setUp() public {
        usdc = new MockUsdc(10000000e18);

        vm.startPrank(treasuryWallet);
        sci = new Sci(treasuryWallet);
        po = new Participation("", treasuryWallet);

        staking = new Staking(treasuryWallet, address(sci));

        govOps = new GovernorOperations(
            address(staking),
            treasuryWallet,
            address(usdc),
            address(sci),
            address(po),
            signer
        );

        govRes = new GovernorResearch(
            address(staking),
            treasuryWallet,
            donationWallet,
            address(usdc),
            address(sci)
        );

        po.setGovOps(address(govOps));
        staking.setGovOps(address(govOps));
        staking.setGovRes(address(govRes));
        govOps.setGovParams("proposalLifeTime", 4 weeks);
        govOps.setGovParams("quorum", 100e18);
        govOps.setGovParams("voteLockTime", 2 weeks);
        govOps.setGovParams("proposeLockTime", 2 weeks);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
        usdc.approve(address(govOps), 100000000000000e6);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(usdc), treasuryWallet, 100000000e6);
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
        deal(address(sci), addr1, 2000000e18);
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
        staking.lock(200e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);

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
        assertEq(details.receivingWallet, opWallet);
        assertTrue(details.payment == GovernorOperations.Payment.Usdc);
        assertEq(details.amount, 5000000e6);
        assertEq(details.amountSci, 0);
        assertEq(details.executable, true);
        vm.stopPrank();
    }

    function test_VoteFor() public {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        govOps.voteStandard(id, true, 2000e18);

        (, , , , uint256 votesFor, uint256 totalVotes, ) = govOps
            .getProposalInfo(id);

        assertEq(votesFor, 2000e18);
        assertEq(totalVotes, 2000e18);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govOps.voteLockTime()));
        vm.stopPrank();
    }

    function test_VoteForProposalWithQuadraticVoting() public {
        vm.startPrank(addr1);
        staking.lock(100e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, true);
        vm.stopPrank();

        
        bool isUnique = true;
        bytes32 messageHash = keccak256(abi.encodePacked(addr1, isUnique));
        console2.logBytes32(messageHash);

        vm.startPrank(signer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(10, messageHash);

        // Construct the signature from the components
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
        vm.startPrank(addr1);
        // Call the voteQV function with the signature
        bool support = true;
        uint votes = 100e18; 

        govOps.voteQV(id, support, votes, isUnique, signature);

        (
            ,
            ,
            ,
            ,
            uint256 votesFor,
            uint256 totalVotes,
            bool quadraticVoting
        ) = govOps.getProposalInfo(id);

        assertEq(votesFor, 10e18);
        assertEq(totalVotes, 10e18);
        assertEq(quadraticVoting, true);

        (, , , uint256 voteLockEnd, , ) = staking.users(addr1);

        assertEq(voteLockEnd, (block.timestamp + govOps.voteLockTime()));
        vm.stopPrank();
    }

    // function test_VerifySignature() public {
    //     address user = addr2;
    //     bool isUnique = false;
    //     // Calculate the message hash
    //     bytes32 messageHash = keccak256(abi.encodePacked(user, isUnique));
    //     // Simulate signing using the signer address
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(10, messageHash);
    //     //ecrecover from foundry accepts messageHash, 
    //     //but ecrecover solidity accepts ethSignedMessage (?)
    //     address recoveredSigner = ecrecover(messageHash, v, r, s);
    //     vm.startPrank(treasuryWallet);
    //     assertEq(recoveredSigner, govOps.getSigner());
    //     vm.stopPrank();

    //     bytes memory signature = abi.encodePacked(r, s, uint8(v));
    //     bool verified = govOps.verify(user, isUnique, signature);
    //     assertTrue(verified, "Not verified");
    // }

    function test_RevertVoteWithVoteLockIfAlreadyVoted() public {
        vm.startPrank(addr2);
        staking.lock(10000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        govOps.voteStandard(id, true, 10000e18);
        bytes4 selector = bytes4(keccak256("VoteLock()"));
        vm.expectRevert(selector);
        govOps.voteStandard(id, true, 1800e18);
        vm.stopPrank();
    }

    function test_RevertVoteWithInsufficientRights() public {
        vm.startPrank(addr2);
        staking.lock(180e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        bytes4 selector = bytes4(
            keccak256("InsufficientVotingRights(uint256,uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, 180e18, 1.8e23));
        govOps.voteStandard(id, true, 1.8e23);
        vm.stopPrank();
    }

    function test_RevertVoteIfProposalInexistent() public {
        vm.startPrank(addr1);
        staking.lock(1.8e23);
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        bytes4 selector = bytes4(keccak256("ProposalInexistent()"));
        vm.expectRevert(selector);
        govOps.voteStandard(1, true, 1.8e28);
        vm.stopPrank();
    }

    function test_RevertIfProposalStillOngoing() public {
        vm.startPrank(addr1);
        staking.lock(180e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
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
        staking.lock(120e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(500e18);
        govOps.voteStandard(id, true, 500e18);
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
        staking.lock(120e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(10e18);
        govOps.voteStandard(id, true, 10e18);
        vm.stopPrank();
        vm.startPrank(addr1);
        vm.warp(4.1 weeks);
        uint256 quorum = govOps.quorum();
        bytes4 selector = bytes4(
            keccak256("QuorumNotReached(uint256,uint256,uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, id, 10e18, quorum));
        govOps.finalize(id);
        vm.stopPrank();
    }

    function test_RevertVoteIfVotingIsFinalized() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        govOps.voteStandard(id, true, 2000e18);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(addr2);
        bytes4 selector = bytes4(keccak256("IncorrectPhase(uint8)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 1));
        govOps.voteStandard(id, true, 2000e18);
        vm.stopPrank();
    }

    function test_RevertFreeTokensWhenVotesLocked() public {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(2000e18);
        govOps.voteStandard(id, true, 2000e18);
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
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(2000e18);
        govOps.voteStandard(id, true, 2000e18);
        (, , , uint256 voteLockEnd, , ) = staking.users(addr2);
        vm.warp(voteLockEnd);
        staking.free(2000e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingUsdc() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000000e6, 0, 0, true, false);
        govOps.voteStandard(id, true, 2000e18);
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
        assertEq(usdc.balanceOf(details.receivingWallet), details.amount);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingSci() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 0, 0, 1000e18, true, false);
        govOps.voteStandard(id, true, 2000e18);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute(id);
        (, , , GovernorOperations.ProjectInfo memory details, , , ) = govOps
            .getProposalInfo(id);

        assertEq(sci.balanceOf(details.receivingWallet), 1000e18);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingSciAndUsdc() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 5000e6, 0, 1000e18, true, false);
        govOps.voteStandard(id, true, 2000e18);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute(id);

        (, , , GovernorOperations.ProjectInfo memory details, , , ) = govOps
            .getProposalInfo(id);

        assertEq(sci.balanceOf(details.receivingWallet), 1000e18);
        assertEq(usdc.balanceOf(details.receivingWallet), 5000e6);
        vm.stopPrank();
    }

    function test_ExecuteProposalUsingCoin() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 0, 1 ether, 0, true, false);
        govOps.voteStandard(id, true, 2000e18);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        govOps.execute{value: 1 ether}(id);

        (, , , GovernorOperations.ProjectInfo memory details, , , ) = govOps
            .getProposalInfo(id);

        assertEq(details.receivingWallet.balance, 1 ether);
        vm.stopPrank();
    }

    function test_RevertProposalIfInvalidInputForExecutable() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        bytes4 selector = bytes4(keccak256("InvalidInputForExecutable()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("Info", opWallet, 5000e6, 500 ether, 0, true, false);
        vm.stopPrank();
    }

    function test_RevertExecutionIfIncorrectMsgValue() public {
        vm.startPrank(addr2);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 0, 500 ether, 0, true, false);
        govOps.voteStandard(id, true, 2000e18);
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
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 0, 500 ether, 0, true, false);
        govOps.voteStandard(id, true, 2000e18);
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
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 0, 500 ether, 0, true, false);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(10e18);
        govOps.voteStandard(id, true, 10e18);
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
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 0, 500 ether, 0, true, true);
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
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 0, 500 ether, 0, true, false);
        vm.stopPrank();
        vm.startPrank(addr1);
        staking.lock(100000e18);
        govOps.voteStandard(id, true, 100000e18);
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
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", opWallet, 0, 500 ether, 0, true, true);
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
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(0), 0, 0, 0, false, false);
        vm.stopPrank();
        vm.startPrank(addr2);
        staking.lock(2000e18);
        govOps.voteStandard(id, true, 2000e18);
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
        staking.lock(2000e18);
        bytes4 selector = bytes4(keccak256("InvalidInfo()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("", opWallet, 500000e6, 0, 0, true, false);
        vm.stopPrank();
    }

    function test_RevertNonExecutableProposalIfPaymentProvided() public {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        bytes4 selector = bytes4(keccak256("InvalidInputForNonExecutable()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("Info", opWallet, 500000e6, 0, 0, false, false);
        vm.stopPrank();
    }

    function test_RevertIfProposeLock() public {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        govOps.propose("Info", address(0), 0, 0, 0, false, false);
        bytes4 selector = bytes4(keccak256("ProposeLock()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("Info", opWallet, 50000e6, 0, 0, true, false);
        vm.stopPrank();
    }

    function test_RevertExecutableProposalIfNoPaymentAndWalletProvided()
        public
    {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        bytes4 selector = bytes4(keccak256("InvalidInputForExecutable()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("Info", address(0), 0, 0, 0, true, false);
        vm.stopPrank();
    }

    function test_RevertExecutableProposalIfNoPaymentButWalletProvided()
        public
    {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        bytes4 selector = bytes4(keccak256("InvalidInputForExecutable()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        govOps.propose("Info", opWallet, 0, 0, 0, true, false);
        vm.stopPrank();
    }

    function test_GovOpsDoesNotWorkAfterTermination() public {
        vm.startPrank(treasuryWallet);
        staking.burnForTermination(2500000e18);
        staking.terminate();
        vm.stopPrank();
        assertEq(govOps.terminated(), true);
        vm.startPrank(addr1);
        bytes4 selector1 = bytes4(keccak256("ContractTerminated(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector1, block.number));
        govOps.propose("Info", opWallet, 500000e6, 0, 0, true, false);
        vm.stopPrank();
    }

    function test_CancelProposalsIfStillOngoingAfterTermination() public {
        vm.startPrank(treasuryWallet);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(0), 0, 0, 0, false, false);
        staking.burnForTermination(2500000e18);
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
        govOps.propose("Info", opWallet, 500000e6, 0, 0, true, false);
        vm.stopPrank();
    }
}
