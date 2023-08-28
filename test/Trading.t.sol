// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/tokens/Trading.sol";
import "contracts/test/Token.sol";

contract TradingTest is Test {

    Trading public trad;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address dao = vm.addr(6);
    address treasuryWallet = vm.addr(8);
    address router = vm.addr(9);
    address govRes = vm.addr(10);

    function setUp() public {
        vm.startPrank(dao);
            trad = new Trading(
                treasuryWallet
            );

            trad.setLLBAToCompleted();
            trad.setFee(100000);
            trad.setRouterAddress(router);
        vm.stopPrank();

        vm.startPrank(addr1);
            trad.approve(router, 1000e18);
            trad.approve(govRes, 1000e18);
        vm.stopPrank();

        vm.startPrank(treasuryWallet);
            trad.transfer(addr1, 1000e18);
            trad.transfer(addr2, 1000e18);
            trad.transfer(addr3, 1000e18);
        vm.stopPrank();

    }

    function test_MaxSupplyMinted() public {
        assertEq(trad.totalSupply(), 18910000e18);
    }

    function test_TransferToAddressWithoutFees() public {
        assertEq(trad.balanceOf(addr1), 1000e18);
    }
    
    function test_RevertSetFeeIfFeeTooHigh() public {
        vm.startPrank(dao);
            bytes4 selector = bytes4(keccak256("SellFeeTooHigh()"));
            vm.expectRevert(selector);
            trad.setFee(1100000);
        vm.stopPrank();
    }

    function test_TransferToRouterWithFees() public {
        vm.startPrank(addr1);
            uint256 balanceTreasuryBeforeTransfer = trad.balanceOf(treasuryWallet);
            trad.transfer(router, 100e18);
            assertEq(trad.balanceOf(treasuryWallet), balanceTreasuryBeforeTransfer + 1e18);
            assertEq(trad.balanceOf(router), 99e18);
        vm.stopPrank();
    }

    function test_TransferFromRouterWithFees() public {
        vm.startPrank(addr1);
            trad.transfer(router, 1000e18);
        vm.stopPrank();
        vm.startPrank(router);
            trad.transfer(addr1, 990e18);
            assertEq(trad.balanceOf(router), 0);
            assertEq(trad.balanceOf(addr1), 990e18);
        vm.stopPrank();
    }

    function test_RevertTransferFromRouterWithFees() public {
        vm.startPrank(addr1);
            trad.transfer(router, 1000e18);
        vm.stopPrank();
        
        vm.startPrank(router);
            vm.expectRevert("ERC20: transfer amount exceeds balance");
            trad.transfer(addr1, 1000e18);
        vm.stopPrank();
    }

    function test_TransferFromWithFees() public {
        vm.startPrank(router);
            uint256 balanceTreasuryBeforeTransfer = trad.balanceOf(treasuryWallet);
            trad.transferFrom(addr1, router, 100e18);
            assertEq(trad.balanceOf(treasuryWallet), balanceTreasuryBeforeTransfer + 1e18);
            assertEq(trad.balanceOf(addr1), 900e18);
            assertEq(trad.balanceOf(router), 99e18);
        vm.stopPrank();
    }

    function test_TransferFromWithoutFees() public {
        vm.startPrank(govRes);
            trad.transferFrom(addr1, govRes, 100e18);
            assertEq(trad.balanceOf(addr1), 900e18);
            assertEq(trad.balanceOf(govRes), 100e18);
        vm.stopPrank();
    }

}