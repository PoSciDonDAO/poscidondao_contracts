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
    address admin = vm.addr(7);

    function setUp() public {
        vm.startPrank(admin);
        sci = new Sci(admin, 18910000);
        vm.stopPrank();
    }

    function test_InitialMinting() public {
        uint256 expectedBalance = 18910000 * 10 ** sci.decimals();
        uint256 actualBalance = sci.balanceOf(admin);
        assertEq(
            actualBalance,
            expectedBalance,
            "Initial minting to the treasury wallet is incorrect"
        );
    }

    function test_BurnTokens() public {
        vm.startPrank(admin);
        sci.burn(1000000e18);
        assertEq(sci.totalSupply(), sci.balanceOf(admin));
        vm.stopPrank();
    }
}
