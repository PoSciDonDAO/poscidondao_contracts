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
    error SameAddress();
    error NoPendingAdmin();
    error NotPendingAdmin(address caller);
    error EmergencyPaused();

    ERC1155Burnable public po;
    IERC20 public sci;
    address public rewardWallet;
    address public pendingAdmin;
    uint256 public conversionRate;
    bool public emergency;

    event Exchanged(
        address user,
        uint256 amount,
        uint256 amountSci
    );
    event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferAccepted(address indexed oldAdmin, address indexed newAdmin);
    event ConversionRateUpdated(uint256 oldRate, uint256 newRate);
    event EmergencySet(bool emergency, uint256 timestamp);

    constructor(address rewardWallet_, address sci_, address po_) {
        rewardWallet = rewardWallet_;
        po = ERC1155Burnable(po_);
        sci = IERC20(sci_);
        conversionRate = 2e18;
        _grantRole(DEFAULT_ADMIN_ROLE, rewardWallet_);
    }

    /**
     * @dev toggles the `emergency` state, which pauses the exchange.
     */
    function setEmergency() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        emergency = !emergency;
        emit EmergencySet(emergency, block.timestamp);
    }

    /**
     * @dev Initiates the transfer of admin role to a new address.
     * The new admin must accept the role by calling acceptAdmin().
     * @param newAdmin The address to be set as the pending admin.
     */
    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert CannotBeZeroAddress();
        if (newAdmin == msg.sender) revert SameAddress();
        if (newAdmin == pendingAdmin) revert SameAddress();
        
        pendingAdmin = newAdmin;
        emit AdminTransferInitiated(msg.sender, newAdmin);
    }

    /**
     * @dev Accepts the admin role transfer. Can only be called by the pending admin.
     */
    function acceptAdmin() external {
        if (pendingAdmin == address(0)) revert NoPendingAdmin();
        if (msg.sender != pendingAdmin) revert NotPendingAdmin(msg.sender);

        address oldAdmin = rewardWallet;
        rewardWallet = pendingAdmin;
        pendingAdmin = address(0);

        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, rewardWallet);

        emit AdminTransferAccepted(oldAdmin, rewardWallet);
    }

    /**
     * @dev Sets a new conversion rate for the PO to SCI exchange. Can only be called by the admin.
     * @param rate The new conversion rate, scaled by 1e18.
     */
    function setConversionRate(uint256 rate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (rate == 0) {
            revert IncorrectInput();
        }
        uint256 oldRate = conversionRate;
        conversionRate = rate;
        emit ConversionRateUpdated(oldRate, rate);
    }

    /**
     * @dev Allows a user to exchange their PO tokens for SCI tokens according to the current conversion rate.
     * Burns a percentage of the SCI tokens as part of the exchange process.
     * @param poAmount The amount of PO tokens to exchange.
     */
    function exchangePoForSci(uint256 poAmount) external nonReentrant {
        if (emergency) revert EmergencyPaused();
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
