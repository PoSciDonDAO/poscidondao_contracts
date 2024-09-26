// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Transaction is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    
    IERC20 public usdc;
    IERC20 public sci;
    address targetWallet;
    uint256 amountUsdc;
    uint256 amountSci;
    Payment payment;

    enum Payment {
        Usdc,
        Sci,
        SciUsdc
    }

    constructor(
        address targetWallet_,
        uint256 amountUsdc_,
        uint256 amountSci_,
        Payment payment_
    ) {
        targetWallet = targetWallet_;
        amountUsdc = amountUsdc_;
        amountSci = amountSci_;
        payment = payment_;
        usdc = IERC20(0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246);
        sci = IERC20(0x8cC93105f240B4aBAF472e7cB2DeC836159AA311);
    }

    /**
     * @dev Execute the proposal using ERC20 tokens (USDC or SCI)
     */
    function execute() external nonReentrant {
        // Handle USDC and SCI transfers
        if (payment == Payment.Usdc || payment == Payment.SciUsdc) {
            _transferToken(usdc, msg.sender, targetWallet, amountUsdc);
        }
        if (payment == Payment.Sci || payment == Payment.SciUsdc) {
            _transferToken(sci, msg.sender, targetWallet, amountSci);
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
