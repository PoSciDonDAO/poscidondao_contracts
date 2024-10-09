// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Transaction is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    address public usdc = 0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246;
    address public sci = 0x8cC93105f240B4aBAF472e7cB2DeC836159AA311;
    address public governorExecutor = 0x4c80b5F7a85B5A6FeA00C7354cBE763e6B426e95;
    address public targetWallet;
    uint256 public amountUsdc;
    uint256 public amountSci;
    address public fundingWallet;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    constructor(
        address fundingWallet_,
        address targetWallet_,
        uint256 amountUsdc_,
        uint256 amountSci_
 
    ) {
        targetWallet = targetWallet_;
        amountUsdc = amountUsdc_;
        amountSci = amountSci_;
        fundingWallet = fundingWallet_;
        _grantRole(GOVERNOR_ROLE, governorExecutor);
    }

    /**
     * @dev Execute the proposal using ERC20 tokens (USDC or SCI)
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        if (amountUsdc > 0) {
            _transferToken(IERC20(usdc), fundingWallet, targetWallet, amountUsdc);
        }
        if (amountSci > 0) {
            _transferToken(IERC20(sci), fundingWallet, targetWallet, amountSci);
        }
    }

    /**
     * @dev Internal function to handle token transfers
     * @param token The ERC20 token to transfer
     * @param from The address to transfer tokens from
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     */
    function _transferToken(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount > 0) {
            bool success = token.transferFrom(from, to, amount);
            require(success, "Token transfer failed");
        }
    }
}
