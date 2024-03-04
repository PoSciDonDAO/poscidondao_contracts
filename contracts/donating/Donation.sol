// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

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
        address asset,
        uint256 donation
    );

    constructor(
        address donationWallet_,
        address treasuryWallet_,
        address usdc_,
        address weth_
    ) {
        donationFraction = 95;
        donationThresholdMatic = 5e17;
        donationThresholdUsdc = 1e6;
        donationThresholdWeth = 1e15;

        donationWallet = donationWallet_;
        treasuryWallet = treasuryWallet_;
        _setupRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
        usdc = usdc_;
        weth = weth_;
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the staking contract address
     * @param usdcAddress the address of the staking contract
     */
    function setUsdcAddress(
        address usdcAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        usdc = usdcAddress;
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
     * @dev sends MATIC donations to the donation & treasury wallet
     * @param user the user that donates the Ether
     */
    function donateMatic(address user) external payable nonReentrant {
        //check if the donation Threshold has been reached
        if (msg.value < donationThresholdMatic) revert InsufficientDonation();

        uint256 amountDonation = (msg.value / 100) * donationFraction;
        uint256 amountTreasury = (msg.value / 100) * (100 - donationFraction);

        //transfer Eth to donation wallet if successful
        (bool sentDonation, ) = donationWallet.call{value: amountDonation}("");
        (bool sentTreasury, ) = treasuryWallet.call{value: amountTreasury}("");
        require(sentDonation && sentTreasury);

        //emit event
        emit DonationCompleted(user, address(0), msg.value);
    }

    /**
     * @dev sends donated USDC to the donation & treasury wallet
     * @param user the user that donates the USDC
     * @param usdcAmount the amount of donated USDC
     */
    function donateUsdc(
        address user,
        uint256 usdcAmount
    ) external nonReentrant {
        //check if the donation Threshold has been reached
        if (usdcAmount < donationThresholdUsdc) revert InsufficientDonation();

        uint256 amountDonation = (usdcAmount / 100) * donationFraction;
        uint256 amountTreasury = (usdcAmount / 100) * (100 - donationFraction);

        //pull usdc from wallet to donation wallet
        IERC20(usdc).safeTransferFrom(user, donationWallet, amountDonation);
        IERC20(usdc).safeTransferFrom(user, treasuryWallet, amountTreasury);

        //emit event
        emit DonationCompleted(user, address(usdc), usdcAmount);
    }

    /**
     * @dev sends donated WETH to the donation & treasury wallet
     * @param user the user that donates the USDC
     * @param wethAmount the amount of donated USDC
     */
    function donateWeth(
        address user,
        uint256 wethAmount
    ) external nonReentrant {
        //check if the donation Threshold has been reached
        if (wethAmount < donationThresholdWeth) revert InsufficientDonation();

        uint256 amountDonation = (wethAmount / 100) * donationFraction;
        uint256 amountTreasury = (wethAmount / 100) * (100 - donationFraction);

        //pull usdc from wallet to donation wallet
        IERC20(weth).safeTransferFrom(user, donationWallet, amountDonation);
        IERC20(weth).safeTransferFrom(user, treasuryWallet, amountTreasury);

        //emit event
        emit DonationCompleted(user, address(weth), wethAmount);
    }
}