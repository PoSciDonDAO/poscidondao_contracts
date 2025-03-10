// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1155Burnable} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * @title PoToSciExchange
 * @dev Implements functionality to exchange PO to SCI
 */
contract PoToSciExchange is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    error CannotBeZeroAddress();
    error IncorrectInput();

    ERC1155Burnable public po;
    IERC20 public sci;
    address public rewardWallet;
    uint256 public conversionRate;

    event Exchanged(
        address user,
        uint256 amount,
        uint256 amountSci
    );
    event RewardWalletSet(address indexed user, address indexed newAddress);

    constructor(address rewardWallet_, address sci_, address po_) {
        rewardWallet = rewardWallet_;
        po = ERC1155Burnable(po_);
        sci = IERC20(sci_);
        conversionRate = 1e18;
        _grantRole(DEFAULT_ADMIN_ROLE, rewardWallet_);

    }

    /**
     * @dev Updates the admin address and transfers admin role.
     * @param newRewardWallet The address to be set as the new admin.
     */
    function setRewardWallet(address newRewardWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRewardWallet == address(0)) revert CannotBeZeroAddress();
        address oldRewardWallet = rewardWallet;
        rewardWallet = newRewardWallet;
        _revokeRole(DEFAULT_ADMIN_ROLE, oldRewardWallet);
        _grantRole(DEFAULT_ADMIN_ROLE, newRewardWallet);
        emit RewardWalletSet(oldRewardWallet, newRewardWallet);
    }

    /**
     * @dev Sets a new conversion rate for the PO to SCI exchange. Can only be called by the admin.
     * @param rate The new conversion rate, scaled by 1e18.
     */
    function setConversionRate(uint256 rate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (rate == 0) {
            revert IncorrectInput();
        }
        conversionRate = rate;
    }

    /**
     * @dev Allows a user to exchange their PO tokens for SCI tokens according to the current conversion rate.
     * Burns a percentage of the SCI tokens as part of the exchange process.
     * @param poAmount The amount of PO tokens to exchange.
     */
    function exchangePoForSci(uint256 poAmount) external nonReentrant {
        if (poAmount == 0) {
            revert IncorrectInput();
        }

        // Calculate the total amount of SCI tokens to mint based on the conversion rate.
        uint256 sciAmount = poAmount * conversionRate;

        // Transfer the net SCI tokens to the user, after deducting the burn amount.
        // Requires approval
        sci.safeTransferFrom(rewardWallet, msg.sender, sciAmount);

        // Burn the specified amount of PO tokens from the user's balance.
        po.burn(msg.sender, 0, poAmount);

        // Emit an event logging the exchange details.
        emit Exchanged(
            msg.sender,
            poAmount,
            sciAmount
        );
    }
}
