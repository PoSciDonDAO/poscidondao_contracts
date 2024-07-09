// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1155Burnable} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * @title PoToSciExchange Contract
 * @dev Contract to exchange Participation (PO) tokens for SCI tokens at a defined rate. 
 * Supports burning a percentage of SCI tokens as part of the exchange.
 */
contract PoToSciExchange is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error IncorrectInput(); // Custom error for invalid input validation.

    /// @notice Interfaces for interacting with the ERC1155Burnable PO token, ERC20Burnable and IERC20 SCI token.
    ERC1155Burnable private po;
    IERC20 private sci;

    /// @notice Address of the wallet holding rewards and responsible for executing token transfers.
    address public rewardWallet;

    /// @notice Conversion rate for exchanging PO tokens to SCI tokens.
    uint256 public conversionRate;

    /// @notice Event to log the exchange activity.
    event Exchanged(
        address user,
        uint256 amount,
        uint256 amountSci
    );

    /**
     * @dev Constructor for initializing the PoToSciExchange contract with necessary addresses and the initial conversion rate.
     * @param rewardWallet_ Address of the rewards wallet.
     * @param sci_ Address of the SCI token contract.
     * @param po_ Address of the PO token contract.
     */
    constructor(address rewardWallet_, address sci_, address po_) {
        rewardWallet = rewardWallet_;
        po = ERC1155Burnable(po_);
        sci = IERC20(sci_);
        _grantRole(DEFAULT_ADMIN_ROLE, rewardWallet_);
        conversionRate = 2e18;
    }

    /**
     * @dev Sets a new conversion rate for the PO to SCI exchange. Can only be called by the admin.
     * @param rate The new conversion rate, scaled by 1e18.
     */
    function setConversionRate(uint256 rate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (rate == 0) {
            revert IncorrectInput();
        }
        conversionRate = rate; // Update the conversion rate, scaled by 1e18.
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
