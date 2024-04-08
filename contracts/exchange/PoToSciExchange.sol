// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
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
    ERC20Burnable private bSci;
    IERC20 private eSci;

    /// @notice Address of the wallet holding rewards and responsible for executing token transfers.
    address public rewardWallet;

    /// @notice Conversion rate for exchanging PO tokens to SCI tokens.
    uint256 public conversionRate;

    /// @notice Event to log the exchange activity.
    event Exchanged(
        address user,
        uint256 poAmount,
        uint256 sciAmountReceived,
        uint256 sciAmountBurned
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
        bSci = ERC20Burnable(sci_);
        eSci = IERC20(sci_);
        _grantRole(DEFAULT_ADMIN_ROLE, rewardWallet_);
        conversionRate = 2e18; // Initial conversion rate, e.g., 2 SCI per PO, scaled by 1e18.
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
     * @param user Address of the user performing the exchange.
     * @param poAmount The amount of PO tokens to exchange.
     */
    function exchangePoForSci(address user, uint256 poAmount) external nonReentrant {
        if (poAmount == 0) {
            revert IncorrectInput();
        }

        // Burn the specified amount of PO tokens from the user's balance.
        po.burn(user, 0, poAmount);

        // Calculate the total amount of SCI tokens to mint based on the conversion rate.
        uint256 sciAmount = poAmount * conversionRate;

        // Calculate the amount of SCI tokens to burn as a percentage of the total.
        uint256 sciAmountToBurn = (sciAmount * 100) / 1000;

        // Transfer the net SCI tokens to the user, after deducting the burn amount.
        eSci.safeTransferFrom(rewardWallet, user, (sciAmount - sciAmountToBurn));

        // Burn the specified amount of SCI tokens from the reward wallet.
        bSci.burnFrom(rewardWallet, sciAmountToBurn);

        // Emit an event logging the exchange details.
        emit Exchanged(
            user,
            poAmount,
            sciAmount - sciAmountToBurn,
            sciAmountToBurn
        );
    }
}
