// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "./../interface/IParticipation.sol";
import "./../interface/ISci.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract PoToSciExchange is AccessControl {
    using SafeERC20 for IERC20;

    error IncorrectInput();

    ///*** INTERFACES ***///
    IParticipation private po;
    ISci private iSci;
    IERC20 private eSci;

    address public rewardWallet;
    uint256 public conversionRate;

    event Exchanged(
        address user,
        uint256 poAmount,
        uint256 sciAmountReceived,
        uint256 sciAmountBurned
    );

    constructor(address rewardWallet_, address sci_, address po_) {
        rewardWallet = rewardWallet_;
        po = IParticipation(po_);
        iSci = ISci(sci_);
        eSci = IERC20(sci_);
        _grantRole(DEFAULT_ADMIN_ROLE, rewardWallet_);
        conversionRate = 2;
    }

    // Set the conversion rate. Only admin can set this.
    function setConversionRate(
        uint256 rate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (rate == 0) {
            revert IncorrectInput();
        }
        conversionRate = rate;
    }

    // Allows an address to exchange their Participation tokens for SCI tokens at the current conversion rate
    function exchangePoForSci(address user, uint256 poAmount) external {
        if (poAmount == 0) {
            revert IncorrectInput();
        }

        // Calculate the amount of SCI tokens to mint based on the conversion rate
        uint256 sciAmount = poAmount * conversionRate * 1e18;

        // Calculate 10% of SCI tokens to burn
        uint256 sciAmountToBurn = (sciAmount * 10) / 100;

        // Mint SCI tokens to the user
        eSci.safeTransferFrom(rewardWallet, user, sciAmount);

        // Burn 10% of SCI tokens
        iSci.burn(user, sciAmountToBurn);

        // Burn Participation tokens
        po.burn(user, poAmount);

        emit Exchanged(
            user,
            poAmount,
            sciAmount - sciAmountToBurn,
            sciAmountToBurn
        );
    }
}
