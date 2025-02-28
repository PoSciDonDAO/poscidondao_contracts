// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./../interfaces/IDon.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

/**
 * @title Donation
 * @dev Facilitates the secure handling of donations within the system.
 * Enables tracking and processing of contributions in a controlled manner.
 * 
 * Security considerations:
 * - Uses ReentrancyGuard to prevent reentrancy attacks
 * - Uses SafeERC20 for secure token transfers
 * - Implements access control for admin functions
 * - Validates all inputs and addresses
 * - Emits events for all important actions
 */
contract Donation is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    // Errors
    error IncorrectPercentage();
    error InsufficientDonation();
    error ZeroAddress();
    error TransferFailed();
    error InvalidAmount();

    // Events
    event Donated(
        address indexed user,
        address indexed asset,
        uint256 amount
    );
    event DonationThresholdUpdated(uint256 newUsdcThreshold, uint256 newEthThreshold);
    event DonationFractionUpdated(uint256 newPercentage);
    event UsdcAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event DonAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event DonationWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event TreasuryWalletUpdated(address indexed oldWallet, address indexed newWallet);

    // State variables
    uint256 public donationFraction;
    uint256 public donationThresholdUsdc;
    uint256 public donationThresholdEth;

    IDon private _don;
    address public usdc;
    address public donationWallet;
    address public treasuryWallet;

    /**
     * @dev Constructor initializes the contract with necessary addresses and default values.
     * @param donationWallet_ Address where donation portion will be sent
     * @param treasuryWallet_ Address where treasury portion will be sent and admin role
     * @param usdc_ Address of the USDC token contract
     * @param don_ Address of the DON token contract
     */
    constructor(
        address donationWallet_,
        address treasuryWallet_,
        address usdc_,
        address don_
    ) {
        if (donationWallet_ == address(0) || 
            treasuryWallet_ == address(0) || 
            usdc_ == address(0) || 
            don_ == address(0)) revert ZeroAddress();

        donationFraction = 95;
        donationThresholdUsdc = 1e6;  // 1 USDC (6 decimals)
        donationThresholdEth = 2.5e14; // 0.00025 ETH

        donationWallet = donationWallet_;
        treasuryWallet = treasuryWallet_;
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
        usdc = usdc_;
        _don = IDon(don_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev Sets the USDC token contract address
     * @param usdcAddress The address of the USDC token contract
     */
    function setUsdcAddress(
        address usdcAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (usdcAddress == address(0)) revert ZeroAddress();
        
        address oldAddress = usdc;
        usdc = usdcAddress;
        
        emit UsdcAddressUpdated(oldAddress, usdcAddress);
    }

    /**
     * @dev Sets the DON token contract address
     * @param donAddress The address of the DON token contract
     */
    function setDonAddress(
        address donAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (donAddress == address(0)) revert ZeroAddress();
        
        address oldAddress = address(_don);
        _don = IDon(donAddress);
        
        emit DonAddressUpdated(oldAddress, donAddress);
    }

    /**
     * @dev Sets the donation wallet address
     * @param newDonationWallet The new donation wallet address
     */
    function setDonationWallet(
        address newDonationWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDonationWallet == address(0)) revert ZeroAddress();
        
        address oldWallet = donationWallet;
        donationWallet = newDonationWallet;
        
        emit DonationWalletUpdated(oldWallet, newDonationWallet);
    }

    /**
     * @dev Sets the treasury wallet address
     * @param newTreasuryWallet The new treasury wallet address
     */
    function setTreasuryWallet(
        address newTreasuryWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasuryWallet == address(0)) revert ZeroAddress();
        
        address oldWallet = treasuryWallet;
        treasuryWallet = newTreasuryWallet;
        
        // Update admin role
        _revokeRole(DEFAULT_ADMIN_ROLE, oldWallet);
        _grantRole(DEFAULT_ADMIN_ROLE, newTreasuryWallet);
        
        emit TreasuryWalletUpdated(oldWallet, newTreasuryWallet);
    }

    /**
     * @dev Sets the minimum threshold amounts for donations
     * @param amountUsdc The minimum amount of USDC that needs to be donated
     * @param amountEth The minimum amount of ETH that needs to be donated
     */
    function setDonationThreshold(
        uint256 amountUsdc,
        uint256 amountEth
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amountUsdc == 0 || amountEth == 0) revert InvalidAmount();
        
        donationThresholdUsdc = amountUsdc;
        donationThresholdEth = amountEth;
        
        emit DonationThresholdUpdated(amountUsdc, amountEth);
    }

    /**
     * @dev Sets the percentage split between donation wallet and treasury
     * @param percentage The percentage of the donation that goes to the donation wallet (95-100)
     */
    function setDonationFraction(
        uint256 percentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (percentage < 95 || percentage > 100) revert IncorrectPercentage();
        
        donationFraction = percentage;
        
        emit DonationFractionUpdated(percentage);
    }

    /**
     * @dev Allows users to donate ETH
     * Splits the donation between donation wallet and treasury according to donationFraction
     * Mints a DON token to the sender as a receipt
     */
    function donateEth() external payable nonReentrant {
        if (msg.value < donationThresholdEth) revert InsufficientDonation();

        uint256 amountDonation = (msg.value * donationFraction) / 100;
        uint256 amountTreasury = msg.value - amountDonation;

        (bool sentDonation, ) = donationWallet.call{value: amountDonation}("");
        if (!sentDonation) revert TransferFailed();
        
        (bool sentTreasury, ) = treasuryWallet.call{value: amountTreasury}("");
        if (!sentTreasury) revert TransferFailed();

        // Mint DON token with donation amount and metadata
        string memory metadata = string(abi.encodePacked(
            "ETH donation: ", 
            Strings.toString(msg.value),
            " at timestamp: ",
            Strings.toString(block.timestamp)
        ));
        
        _don.mint(msg.sender, msg.value, metadata);

        emit Donated(msg.sender, address(0), msg.value);
    }

    /**
     * @dev Allows users to donate USDC
     * @param usdcAmount The amount of USDC to donate
     * Splits the donation between donation wallet and treasury according to donationFraction
     * Mints a DON token to the sender as a receipt
     */
    function donateUsdc(uint256 usdcAmount) external nonReentrant {
        if (usdcAmount < donationThresholdUsdc) revert InsufficientDonation();

        uint256 amountDonation = (usdcAmount * donationFraction) / 100;
        uint256 amountTreasury = usdcAmount - amountDonation;

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
        
        // Mint DON token with donation amount and metadata
        string memory metadata = string(abi.encodePacked(
            "USDC donation: ", 
            Strings.toString(usdcAmount),
            " at timestamp: ",
            Strings.toString(block.timestamp)
        ));
        
        _don.mint(msg.sender, usdcAmount, metadata);

        emit Donated(msg.sender, address(usdc), usdcAmount);
    }

    /**
     * @dev Returns the address of the DON token contract
     * @return The address of the DON token contract
     */
    function getDonAddress() external view returns (address) {
        return address(_don);
    }
}
