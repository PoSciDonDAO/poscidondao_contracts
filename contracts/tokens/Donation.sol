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
    
    uint256 private _donationThresholdEth;
    uint256 private _donationThresholdUsdc;
    uint256 private _donationFraction;

    address public donationWallet;
    address public treasuryWallet;
    address public usdc;

    mapping(address => uint256) private _balances;

    event DonationCompleted(address indexed user, uint256 donation);

    constructor(
        address _usdc,
        address _donationWallet,
        address _treasuryWallet
    ) {
        _donationFraction = 95;
        _donationThresholdEth = 1e15;
        _donationThresholdUsdc = 1e6;
        usdc = _usdc;
        donationWallet = _donationWallet;
        treasuryWallet = _treasuryWallet;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    
    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the staking contract address
     * @param usdcAddress the address of the staking contract
     */
    function setUsdcAddress(address usdcAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        usdc = usdcAddress;
    }

    /**
     * @dev sets the Threshold to donate usdc or eth
     * @param amountUsdc the least amount of USDC that needs be donated  
     * @param amountEth the least amount of ETH that needs be donated  
     */
    function setDonationThreshold(uint256 amountUsdc, uint256 amountEth) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _donationThresholdUsdc = amountUsdc;
        _donationThresholdEth = amountEth;
    }

    /**
     * @dev sets the donated amount that will go to the donation wallet and treasury
     */
    function setDonationFraction(uint256 percentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(percentage < 95) revert IncorrectPercentage();
        _donationFraction = percentage;
    }

    /**
     * @dev sends Eth donations to the donation wallet, 
     * donor receives DON tokens.
     * ! Per 0.001 ETH --> ethPrice/1000 DON Token !
     * @param user the user that donates the Ether 
     */
    function donateEth(address user) external payable nonReentrant {
        //check if the donation Threshold has been reached
        if (msg.value < _donationThresholdEth) revert InsufficientDonation();

        uint256 amountDonation = msg.value / 100 * _donationFraction;
        uint256 amountTreasury = msg.value / 100 * (100 - _donationFraction);

        //transfer Eth to donation wallet if successful
        (bool sentDonation,) = donationWallet.call{value: amountDonation}("");
        (bool sentTreasury,) = treasuryWallet.call{value: amountTreasury}("");
        require(sentDonation && sentTreasury);

        //emit event
        emit DonationCompleted(user, msg.value);
    }

    /**
     * @dev sends donated USDC to the donation wallet 
     * donor receives DON tokens based on the given ratio.
     * @param usdcAmount the amount of donated USDC
     * @param user the user that donates the USDC  
     */
    function donateUsdc(address user, uint256 usdcAmount) external nonReentrant {
        //check if the donation Threshold has been reached
        if (usdcAmount < _donationThresholdUsdc) revert InsufficientDonation();

        uint256 amountDonation = usdcAmount / 100 * _donationFraction;
        uint256 amountTreasury = usdcAmount / 100 * (100 - _donationFraction);

        //pull usdc from wallet to donation wallet
        IERC20(usdc).safeTransferFrom(user, donationWallet, amountDonation);
        IERC20(usdc).safeTransferFrom(user, treasuryWallet, amountTreasury);

        //emit event
        emit DonationCompleted(user, usdcAmount);
    }
}
