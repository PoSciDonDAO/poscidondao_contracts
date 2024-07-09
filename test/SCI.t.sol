// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Sci.sol";
import "contracts/staking/Staking.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/tokens/Po.sol";

contract SciTest is Test {
    Sci public sci;
    Staking public staking;
    GovernorOperations public govOps;
    MockUsdc public usdc;
    Po public po;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address treasuryWallet = vm.addr(7);
    address govRes = vm.addr(8);
    address opWallet = vm.addr(9);
    address signer = vm.addr(10);

    function setUp() public {
        vm.startPrank(treasuryWallet);
        usdc = new MockUsdc(10000000e18);
        sci = new Sci(treasuryWallet, 4538400);
        po = new Po("", treasuryWallet);
        staking = new Staking(treasuryWallet, address(sci));

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
        sci.setGovOps(address(govOps));
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        sci.approve(address(govOps), 100000000000000e18);
        sci.approve(address(staking), 1000000000000e18);
        deal(address(sci), addr1, 200000000e18);
        deal(addr1, 10000 ether);
        vm.stopPrank();
    }

    function test_InitialMinting() public {
        uint256 expectedBalance = 4538400 * 10 ** sci.decimals();
        uint256 actualBalance = sci.balanceOf(treasuryWallet);
        assertEq(
            actualBalance,
            expectedBalance,
            "Initial minting to the treasury wallet is incorrect"
        );
    }

    function test_RevertMintingTokensManually() public {
        vm.startPrank(treasuryWallet);
        bytes4 selector = bytes4(keccak256("Unauthorized(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, treasuryWallet));
        sci.mint(5000e18);
        vm.stopPrank();
    }

    function test_MintTokensAfterMintingProposal() public {
        vm.startPrank(addr1);
        staking.lock(20000000e18);
        assertEq(sci.totalSupply(), sci.balanceOf(treasuryWallet));
        uint256 id = govOps.getProposalIndex();
        govOps.propose(
            "Info",
            address(0),
            0,
            0,
            5000000e18,
            GovernorOperations.ProposalType.Minting,
            false
        );
        govOps.voteStandard(id, true, 20000000e18);
        vm.warp(4.1 weeks);
        govOps.finalize(id);
        (, , , GovernorOperations.ProjectInfo memory details, , , ) = govOps
            .getProposalInfo(id);
        assertTrue(details.proposalType == GovernorOperations.ProposalType.Minting);
        assertEq(details.amountSci, 5000000e18);
        vm.stopPrank();
        vm.startPrank(treasuryWallet);
        uint256 balanceBeforeMinting = sci.balanceOf(treasuryWallet);
        govOps.execute(id);
        assertEq(sci.totalSupply(), balanceBeforeMinting + 5e24);
        vm.stopPrank();
    }

    function test_BurnTokens() public {
        vm.startPrank(treasuryWallet);
        sci.burn(1000000e18);
        assertEq(sci.totalSupply(), sci.balanceOf(treasuryWallet));
        vm.stopPrank();
    }
}
