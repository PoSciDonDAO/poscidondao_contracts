// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/governance/GovernorOperations.sol";
import "contracts/tokens/Po.sol";
import "contracts/test/MockUsdc.sol";
import "contracts/tokens/Sci.sol";
import "contracts/staking/Staking.sol";
import "contracts/exchange/PoToSciExchange.sol";

contract PoToSciExchangeTest is Test {
    GovernorOperations public govOps;
    Po public po;
    MockUsdc public usdc;
    Staking public staking;
    Sci public sci;
    PoToSciExchange public ex;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address admin = vm.addr(6);
    address donationWallet = vm.addr(7);
    address operationsWallet = vm.addr(8);
    address rewardWallet = vm.addr(9);
    address signer = vm.addr(10);
    string info = "Info";
    bytes32 govIdCircuitId =
        0x729d660e1c02e4e419745e617d643f897a538673ccf1051e093bbfa58b0a120b;
    bytes32 phoneCircuitId =
        0xbce052cf723dca06a21bd3cf838bc518931730fb3db7859fc9cc86f0d5483495;

    function setUp() public {
        usdc = new MockUsdc(10000000e6);

        vm.startPrank(admin);
        sci = new Sci(admin, 18910000);

        po = new Po("", admin);
        staking = new Staking(admin, address(sci));

        govOps = new GovernorOperations(
            address(staking),
            admin,
            address(sci),
            address(po),
            signer,
            addr2
        );

        ex = new PoToSciExchange(rewardWallet, address(sci), address(po));

        govOps.setPoToken(address(po));
        staking.setSciToken(address(sci));
        staking.setGovOps(address(govOps));
        po.setGovOps(address(govOps));
        vm.stopPrank();

        vm.startPrank(rewardWallet);
        deal(rewardWallet, 100000 ether);
        deal(address(sci), rewardWallet, 100000000e18);
        usdc.approve(address(govOps), 100000000000000e18);
        sci.approve(address(ex), 10000000000000000e18);
        vm.stopPrank();

        vm.startPrank(addr1);
        deal(address(sci), addr1, 100000000e18);
        deal(addr1, 10000 ether);
        sci.approve(address(govOps), 10000e18);
        sci.approve(address(staking), 10000000000000000e18);
        staking.lock(10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
        deal(address(sci), addr2, 5000e18);
        deal(addr2, 10000 ether);
        sci.approve(address(govOps), 10000e18);
        sci.approve(address(staking), 10000000000000000e18);
        po.setApprovalForAll(address(ex), true);
        vm.stopPrank();
    }

    function test_SetConversionRate() public {
        vm.startPrank(rewardWallet);
        ex.setConversionRate(5e18);
        assertEq(ex.conversionRate(), 5e18);
        vm.stopPrank();
    }

    function test_ExchangePoForSci() public {
        vm.startPrank(addr1);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(0), false);

        vm.stopPrank();
        vm.startPrank(addr2);

        staking.lock(5000e18);

        govOps.voteStandard(id, true);
        assertEq(po.balanceOf(addr2, 0), 1);

        ex.exchangePoForSci(1);
        assertEq(po.balanceOf(addr2, 0), 0);
        assertEq(sci.balanceOf(addr2), 2e18);
        vm.stopPrank();
    }

    function test_ExchangeForSmallAmountsOfSci() public {
        vm.startPrank(rewardWallet);
        ex.setConversionRate(5e17);
        vm.stopPrank();

        vm.startPrank(addr1);
        staking.lock(2000e18);
        uint256 id = govOps.getProposalIndex();
        govOps.propose("Info", address(0), false);
        vm.stopPrank();

        vm.startPrank(addr2);
        staking.lock(5000e18);
        govOps.voteStandard(id, true);

        ex.exchangePoForSci(1);
        assertEq(po.balanceOf(addr2, 0), 0);
        assertEq(sci.balanceOf(addr2), 5e17);
    }
}
