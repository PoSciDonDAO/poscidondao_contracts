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
    address fundingWallet;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    constructor(
        address targetWallet_,
        uint256 amountUsdc_,
        uint256 amountSci_,
        address govExecAddress_,
        address fundingWallet_,
        address usdc_,
        address sci_
    ) {
        targetWallet = targetWallet_;
        amountUsdc = amountUsdc_;
        amountSci = amountSci_;
        fundingWallet = fundingWallet_;
        usdc = IERC20(usdc_);
        sci = IERC20(sci_);
        _grantRole(GOVERNOR_ROLE, govExecAddress_);
    }

    /**
     * @dev Execute the proposal using ERC20 tokens (USDC or SCI)
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        if (amountUsdc > 0) {
            _transferToken(usdc, fundingWallet, targetWallet, amountUsdc);
        }
        if (amountSci > 0) {
            _transferToken(sci, fundingWallet, targetWallet, amountSci);
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
