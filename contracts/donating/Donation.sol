// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Copyright (c) 2024, PoSciDonDAO Foundation.
 * 
 * This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero 
 * General Public License as published by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
 * implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public 
 * License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License along with this program.  If not, 
 * see <http://www.gnu.org/licenses/>.
 */
pragma solidity ^0.8.19;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/// @title Donation Contract
/// @notice Allows users to donate USDC, WETH or MATIC to a specified donation and treasury wallet.
/// @dev This contract utilizes OpenZeppelin's SafeERC20, ReentrancyGuard, and AccessControl for secure and role-based interactions.
contract Donation is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error IncorrectPercentage();
    error InsufficientDonation();

    uint256 public donationFraction;
    uint256 public donationThresholdMatic;
    uint256 public donationThresholdUsdc; 
    uint256 public donationThresholdWeth;

    address public donationWallet;
    address public treasuryWallet;
    address public usdc;
    address public weth;

    event DonationCompleted(
        address indexed user,
        address indexed asset,
        uint256 amount
    );

    /**
     * @notice Initializes contract with key wallet addresses & thresholds.
     * @param donationWallet_ Address of the donation wallet.
     * @param treasuryWallet_ Address of the treasury wallet.
     * @param usdc_ Address of the USDC token contract.
     * @param weth_ Address of the WETH token contract.
     */
    constructor(
        address donationWallet_,
        address treasuryWallet_,
        address usdc_,
        address weth_
    ) {
        donationFraction = 95;
        donationThresholdMatic = 1e17; //0.1 MATIC
        donationThresholdUsdc = 1e5; //0.1 USDC
        donationThresholdWeth = 1e14; //0.0001 WETH

        donationWallet = donationWallet_;
        treasuryWallet = treasuryWallet_;

        usdc = usdc_;
        weth = weth_;

        _setupRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev Sets the address of the USDC token contract
     * @param usdcAddress The USDC contract address
     */
    function setUsdcAddress(
        address usdcAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        usdc = usdcAddress;
    }

    /**
     * @dev Sets the address of the WETH token contract
     * @param wethAddress the WETH contract address
     */
    function setWethAddress(
        address wethAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        weth = wethAddress;
    }

    /**
     * @dev sets the Threshold to donate USDC, MATIC or WETH
     * @param amountUsdc the least amount of USDC that needs be donated
     * @param amountMatic the least amount of MATIC that needs be donated
     * @param amountWeth the least amount of WETH that needs be donated
     */
    function setDonationThreshold(
        uint256 amountUsdc,
        uint256 amountMatic,
        uint256 amountWeth
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        donationThresholdUsdc = amountUsdc;
        donationThresholdMatic = amountMatic;
        donationThresholdWeth = amountWeth;
    }

    /**
     * @dev sets the donated amount that will go to the donation wallet and treasury
     */
    function setDonationFraction(
        uint256 percentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (percentage < 95) revert IncorrectPercentage();
        donationFraction = percentage;
    }

    /**
     * @dev Sends MATIC to the donation & treasury wallet
     */
    function donateMatic() external payable nonReentrant {
        if (msg.value < donationThresholdMatic) revert InsufficientDonation();

        uint256 amountDonation = (msg.value / 100) * donationFraction;
        uint256 amountTreasury = (msg.value / 100) * (100 - donationFraction);

        (bool sentDonation, ) = donationWallet.call{value: amountDonation}("");
        (bool sentTreasury, ) = treasuryWallet.call{value: amountTreasury}("");
        require(sentDonation && sentTreasury);

        //emit event
        emit DonationCompleted(msg.sender, address(0), msg.value);
    }

    /**
     * @dev Sends USDC to the donation & treasury wallets
     * @param usdcAmount The amount of donated USDC
     */
    function donateUsdc(
        uint256 usdcAmount
    ) external nonReentrant {
        if (usdcAmount < donationThresholdUsdc) revert InsufficientDonation();

        uint256 amountDonation = (usdcAmount / 100) * donationFraction;
        uint256 amountTreasury = (usdcAmount / 100) * (100 - donationFraction);

        IERC20(usdc).safeTransferFrom(msg.sender, donationWallet, amountDonation);
        IERC20(usdc).safeTransferFrom(msg.sender, treasuryWallet, amountTreasury);

        //emit event
        emit DonationCompleted(msg.sender, address(usdc), usdcAmount);
    }

    /**
     * @dev Sends WETH to the donation & treasury wallets
     * @param wethAmount the amount of donated WETH
     */
    function donateWeth(
        uint256 wethAmount
    ) external nonReentrant {
        if (wethAmount < donationThresholdWeth) revert InsufficientDonation();

        uint256 amountDonation = (wethAmount / 100) * donationFraction;
        uint256 amountTreasury = (wethAmount / 100) * (100 - donationFraction);

        IERC20(weth).safeTransferFrom(msg.sender, donationWallet, amountDonation);
        IERC20(weth).safeTransferFrom(msg.sender, treasuryWallet, amountTreasury);

        //emit event
        emit DonationCompleted(msg.sender, address(weth), wethAmount);
    }
}
