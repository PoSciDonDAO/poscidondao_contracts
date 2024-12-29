// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./../interfaces/IDon.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title Donation
 * @dev Facilitates the secure handling of donations within the system.
 * Enables tracking and processing of contributions in a controlled manner.
 */
contract Donation is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error IncorrectPercentage();
    error InsufficientDonation();

    uint256 public donationFraction;
    uint256 public donationThresholdUsdc;
    uint256 public donationThresholdEth;

    IDon private _don;
    address public usdc;
    address public donationWallet;
    address public treasuryWallet;

    event Donated(
        address indexed user,
        address indexed asset,
        uint256 amount
    );

    constructor(
        address donationWallet_,
        address treasuryWallet_,
        address usdc_,
        address don_
    ) {
        donationFraction = 95;
        donationThresholdUsdc = 1e6;
        donationThresholdEth = 2.5e14;

        donationWallet = donationWallet_;
        treasuryWallet = treasuryWallet_;
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
        usdc = usdc_;
        _don = IDon(don_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the sciManager contract address
     * @param usdcAddress the address of the sciManager contract
     */
    function setUsdcAddress(
        address usdcAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        usdc = usdcAddress;
    }

    /**
     * @dev sets the Threshold to donate USDC, ETH or WETH
     * @param amountUsdc the least amount of USDC that needs be donated
     * @param amountEth the least amount of WETH that needs be donated
     */
    function setDonationThreshold(
        uint256 amountUsdc,
        uint256 amountEth
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        donationThresholdUsdc = amountUsdc;
        donationThresholdEth = amountEth;
    }

    /**
     * @dev sets the donated amount that will go to the donation wallet and treasury.
     * @param percentage the percentage of the donation.
     */
    function setDonationFraction(
        uint256 percentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (percentage < 95) revert IncorrectPercentage();
        donationFraction = percentage;
    }

    /**
     * @dev sends ETH donations to the donation & treasury wallet
     */
    function donateEth() external payable nonReentrant {
        if (msg.value < donationThresholdEth) revert InsufficientDonation();

        uint256 amountDonation = (msg.value / 100) * donationFraction;
        uint256 amountTreasury = (msg.value / 100) * (100 - donationFraction);

        (bool sentDonation, ) = donationWallet.call{value: amountDonation}("");
        (bool sentTreasury, ) = treasuryWallet.call{value: amountTreasury}("");
        require(sentDonation && sentTreasury);

        _don.mint(msg.sender, 1);

        emit Donated(msg.sender, address(0), msg.value);
    }

    /**
     * @dev sends donated USDC to the donation & treasury wallet
     * @param usdcAmount the amount of donated USDC
     */
    function donateUsdc(uint256 usdcAmount) external nonReentrant {
        if (usdcAmount < donationThresholdUsdc) revert InsufficientDonation();

        uint256 amountDonation = (usdcAmount / 100) * donationFraction;
        uint256 amountTreasury = (usdcAmount / 100) * (100 - donationFraction);

        IERC20(usdc).safeTransferFrom(
            msg.sender,
            donationWallet,
            amountDonation
        );
        IERC20(usdc).safeTransferFrom(
            msg.sender,
            treasuryWallet,
            amountTreasury
        );
        
        _don.mint(msg.sender, 1);

        emit Donated(msg.sender, address(usdc), usdcAmount);
    }
}
