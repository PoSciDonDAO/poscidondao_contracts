// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "contracts/tokens/Sci.sol";
import "contracts/exchange/Swap.sol";
import "contracts/test/Usdc.sol";
import "contracts/DeployedAddresses.sol";
import "contracts/DeployedPresaleAddresses.sol";

contract SwapTest is Test {
    Usdc usdc;

    Sci sci;
    Swap swap;

    address addr1 = 0x690BF2dB31D39EE0a88fcaC89117b66a588E865a;
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address admin = DeployedAddresses.admin;

    // address[] membersWhitelist = [
    //     0x690BF2dB31D39EE0a88fcaC89117b66a588E865a,
    //     0xb101a90f179d8eE815BDb0c8315d4C28f8FA5b99,
    //     0xF7dd52707034696eFd21AcbDAbA4e3dE555BD488,
    //     0xD784862aaA7848Be9C0dcA50958Da932969ef41d,
    //     0xFF77ABCA900514BE62374b3F86bacEa033365088,
    //     0xD2f8B7A8BA93eA9e14f7bc421a70118da8508E9b,
    //     0xd8C98B84755056d193837a5e5b7814c8f6b10590,
    //     0x51d93270eA1aD2ad0506c3BE61523823400E114C,
    //     0x8b672551D687256BFaB5e447550200Eb625891De,
    //     0x9BD74d27C123FF1aC9fe82132F45662865A51c43,
    //     0x0F22D9e9421C02E60fFF8823e3d0Ccc4780F5750,
    //     0xe4c4E389ffF80E18C63df4691a16ec575781Ca0A,
    //     0x3aBCDd4b604385659E34b186d5c0aDB9FFE0403C,
    //     0x74Da8f4B8A459DaD4B7327f2eFaB2516D140A7aB,
    //     0x2E3fe68Bee7922e94EEfc643b1F04E71C6294E93,
    //     0xc3d7F06db7E0863DbBa355BaC003344887EEe455,
    //     0x39E39b63ac98b15407aBC057155d0fc296C11FE4,
    //     0x7DDAfD8EDEaf1182BBF7983c4D778C046a17D9f1,
    //     0x23208D88Ea974cc4AA639E84D2b1074D4fb41ac9,
    //     0x62B9c3eDef0aDBE15224c8a3f8824DBDEB334e9f,
    //     0xFeEf239AE6D6361729fcB8b4Ea60647344d87FEE,
    //     0x256ecFb23cF21af9F9E33745c77127892956a687,
    //     0x507b0AB4d904A38Dd8a9852239020A5718157EF6,
    //     0xAEa5981C8B3D66118523549a9331908136a3e648,
    //     0x82Dd06dDC43A4cC7f4eF68833D026C858524C2a9,
    //     0xb42a22ec528810aE816482914824e47F4dc3F094,
    //     0xe1966f09BD13e92a5aCb18C486cE4c696347A25c,
    //     0x1c033d7cb3f57d6772438f95dF8068080Ef23dc9,
    //     0x91fd6Ceb1D67385cAeD16FE0bA06A1ABC5E1312e,
    //     0x083BcEEb941941e15a8a2870D5a4922b5f07Cc81,
    //     0xe5E3aa6188Bd53Cf05d54bB808c0F69B3E658087,
    //     0x1a1c7aB8C4824d4219dc475932b3B8150E04a79C
    // ];

    function setUp() public {

        usdc = Usdc(DeployedAddresses.usdc);
        vm.startPrank(admin);
        sci = Sci(DeployedAddresses.sci);
        swap = Swap(DeployedPresaleAddresses.swap);
        // deal(address(sci), admin, 100000000e18);
        sci.approve(DeployedPresaleAddresses.swap, 94550e18);
        // address[] memory whitelist = new address[](2);
        // whitelist[0] = addr1;
        // whitelist[1] = addr2;
        // swap.addMembersToWhitelist(whitelist);
        vm.stopPrank();

        vm.startPrank(addr1);
        usdc.approve(address(swap), 10000000e6);
        deal(addr1, 10000000 ether);
        deal(address(usdc), addr1, 1000000e6);
        vm.stopPrank();

        vm.startPrank(addr4);
        usdc.approve(address(swap), 10000000e6);
        deal(addr4, 10000000 ether);
        deal(address(usdc), addr4, 1000000e6);
        vm.stopPrank();
    }

    function testSwapUsdcSuccess() public {
        uint256 oldBalanceAdmin = usdc.balanceOf(admin);
        uint256 oldBalanceAddr1 = sci.balanceOf(addr1);
        uint256 amount = swap.currentEtherPrice();
        uint256 expectedSciAmount = ((amount * 10000) / swap.priceInUsdc()) * 1e12;

        vm.startPrank(addr1);
        usdc.approve(address(swap), amount);
        swap.swapUsdc(amount);

        assertEq(usdc.balanceOf(admin), oldBalanceAdmin + amount);
        assertEq(
            sci.balanceOf(addr1),
            oldBalanceAddr1 + expectedSciAmount,
            "User SCI balance should increase"
        );

        vm.stopPrank();
    }

    function testSwapEthSuccess() public {
        uint256 oldBalanceAdmin = admin.balance;
        uint256 oldBalanceAddr1 = sci.balanceOf(addr1);

        uint256 amount = 1 ether;
        uint256 expectedSciAmount = amount * swap.ethToSciConversionRate();

        vm.startPrank(addr1);
        swap.swapEth{value: amount}();

        assertEq(
            address(admin).balance,
            oldBalanceAdmin + amount,
            "Treasury ETH balance should increase"
        );
        assertEq(
            sci.balanceOf(addr1),
            oldBalanceAddr1 + expectedSciAmount,
            "User SCI balance should increase"
        );

        vm.stopPrank();
    }

    function testRevertSwapUsdcNotWhitelisted() public {
        uint256 amount = 10000e6;

        vm.startPrank(addr4);
        usdc.approve(address(swap), amount);
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        swap.swapUsdc(amount);
        vm.stopPrank();
    }

    function testRevertSwapEthNotWhitelisted() public {
        uint256 amount = 1e18;

        vm.startPrank(addr4);
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        swap.swapEth{value: amount}();
        vm.stopPrank();
    }

    function testRevertSwapUsdcSaleExpired() public {
        vm.warp(block.timestamp);
        uint256 amount = 1000e6;

        vm.startPrank(addr1);
        usdc.approve(address(swap), amount);
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(abi.encodeWithSignature("SaleExpired()"));
        swap.swapUsdc(amount);
        vm.stopPrank();
    }

    function testRevertSwapEthSaleExpired() public {
        vm.warp(block.timestamp);
        uint256 amount = 1 ether;

        vm.startPrank(addr1);
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(abi.encodeWithSignature("SaleExpired()"));
        swap.swapEth{value: amount}();
        vm.stopPrank();
    }

    function testRevertSwapEthLimitReached() public {
        uint256 amount = 1.00001 ether;

        vm.startPrank(addr1);
        vm.expectRevert(abi.encodeWithSignature("CannotSwapMoreThanOneEther()"));
        swap.swapEth{value: amount}();
        vm.stopPrank();
    }

    function testRevertSwapUsdcLimitReached() public {
        uint256 amount = swap.currentEtherPrice() + 1e6;

        vm.startPrank(addr1);
        vm.expectRevert(abi.encodeWithSignature("CannotSwapMoreThanOneEther()"));
        swap.swapUsdc(amount);
        vm.stopPrank();
    }

    // function testRevertSwapEthSoldOut() public {
    //     uint256 cap = swap.sciSwapCap();
    //     uint256 largeAmountEth = cap / swap.rateEth();
    //     vm.startPrank(addr1);
    //     vm.expectRevert(abi.encodeWithSignature("SoldOut()"));
    //     swap.swapEth{value: largeAmountEth}();
    //     vm.stopPrank();
    // }
}
