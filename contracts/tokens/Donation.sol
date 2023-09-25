// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "contracts/interface/IDonation.sol";

contract Donation is IDonation, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    error AccountBound();
    error IncorrectAddress();
    error IncorrectPercentage();
    error InsufficientBalance();
    error InsufficientDonation();
    error InsufficientStake();
    error Unauthorized(address user);

    string  private _name;
    string  private _symbol;
    uint16  private _decimals;
    uint256 private _totalSupply;    
    uint256 private _donationThresholdEth;
    uint256 private _donationThresholdUsdc;
    uint256 private _ratioEth;
    uint256 private _ratioUsdc;
    uint256 private _donationFraction;
    address private _stakingContract;

    address public donationWallet;
    address public treasuryWallet;
    address public usdc;

    mapping(address => uint256) private _balances;
    mapping(address => uint256) public wards;
    mapping(address => uint256) public stake;

    modifier dao() {
        if(wards[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyStake() {
        if(msg.sender != _stakingContract) revert Unauthorized(msg.sender);
        _;
    }

    event Rely(address indexed user);
    event Deny(address indexed user);
    event Push(address indexed user, uint256 amount);
    event Pull(address indexed user, uint256 amount);
    event DonationCompleted(address indexed user, uint256 donation, uint256 tokenAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(
        address _usdc,
        address _donationWallet,
        address _treasuryWallet
    ) {
        _name = "Donation Token";
        _symbol = "DON";
        _decimals = 18;
        _donationFraction = 95;
        _donationThresholdEth = 1e15;
        _donationThresholdUsdc = 1e6;
        _ratioEth = 1800;
        _ratioUsdc = 10;
        usdc = _usdc;
        donationWallet = _donationWallet;
        treasuryWallet = _treasuryWallet;

        wards[msg.sender] = 1;
    }
    
    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the staking contract address
     * @param stakingContract_ the address of the staking contract
     */
    function setStakingContract(address stakingContract_) external dao {
        _stakingContract = stakingContract_;
    }

    /**
     * @dev sets the staking contract address
     * @param usdcAddress the address of the staking contract
     */
    function setUsdcAddress(address usdcAddress) external dao {
        usdc = usdcAddress;
    }

    /**
     * @dev adds a dao
     * @param user the user that becomes a dao
     */
    function addWard(address user) external dao {
        wards[user] = 1;
        emit Rely(user);
    }

    /**
     * @dev removes a dao
     * @param user the user that will be removed as a dao.
     */
    function removeWard(address user) external dao {
        if(wards[user] != 1) {
            revert Unauthorized(user);
        }
        delete wards[user];
        emit Deny(user);
    }

    /**
     * @dev sets the ratio of the ETH to DON token conversion 
     */
    function setRatioEth(uint256 _n, uint256 _d) external dao {
        _ratioEth = 1000 * _n / _d;
    }

    /**
     * @dev sets the ratio of the USDC to DON token conversion 
     */
    function setRatioUsdc(uint256 _n, uint256 _d) external dao {
        _ratioUsdc = 10 * _n / _d;
    }

    /**
     * @dev sets the Threshold to donate usdc or eth
     * @param amountUsdc the least amount of USDC that needs be donated  
     * @param amountEth the least amount of ETH that needs be donated  
     */
    function setDonationThreshold(uint256 amountUsdc, uint256 amountEth) external dao {
        _donationThresholdUsdc = amountUsdc;
        _donationThresholdEth = amountEth;
    }

    function setDonationFraction(uint256 percentage) external dao {
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
        
        //determine the amount of DON tokens issued
        uint256 amount = msg.value * _ratioEth;

        //mint DON tokens
        _mint(user, amount);

        //emit event
        emit DonationCompleted(user, msg.value, amount);
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
        
        //calculate amount of don tokens 
        uint256 amount = usdcAmount * _ratioUsdc / 10 * 10e11;

        //mint don tokens to function caller
        _mint(user, amount);

        //emit event
        emit DonationCompleted(user, usdcAmount, amount);
    }

    /**
     * @dev pushes tokens from user to the staking contract
     * @param user the user that wants to push their DON tokens
     * @param amount the amount of tokens that need to be pushed
     */
    function push(
        address user,
        uint256 amount
    ) external onlyStake {

        //transfer from user to daoernance contract
        _transfer(user, _stakingContract, amount);

        //update staked amount
        stake[user] += amount;

        //emit Push event
        emit Push(user, amount);
    }
    
    /**
     * @dev pulls tokens from staking contract to user
     * @param user the user that wants to pull their DON tokens
     * @param amount the amount of tokens that need to be pulled
     */
    function pull(
        address user,
        uint256 amount
    ) external onlyStake {
        if (stake[user] < amount) revert InsufficientStake();
        
        //transfer from staking contract to holder
        _transfer(_stakingContract, user, amount);
        
        //subtract the pulled amount            
        stake[user] -= amount;

        //emit Pull event
        emit Pull(user, amount);
    }

    /**
     * @dev allows you to burn your DON tokens
     * @param amount of tokens that will be burned
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    } 

    //internal functions
    /**
     * @dev mints DON tokens
     * @param account account of the donor
     * @param amount amount of DON tokens that will be minted
     */
    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert IncorrectAddress();

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, 
     * usually a shorter version of the name.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev returns the decimals of the token
     */
    function decimals() external view returns (uint16) {
        return _decimals;
    }

    /**
     * @dev returns the total supply of the token
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev returns the balance of an account
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev returns the staking contract
     */
    function stakingContract() external view returns (address) {
        return _stakingContract;
    }

    ///*** INTERNAL FUNCTIONS ***///

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     * @param account account of the donor
     * @param amount amount of DON tokens that will be burned
     */
    function _burn(address account, uint256 amount) internal virtual {
        if (account == address(0)) revert IncorrectAddress();

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        if (accountBalance < amount) revert InsufficientBalance();
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    /**
    * @dev Transfer of tokens from smart contract to contributors. 
    * @param from issuer of tokens.
    * @param to token recipient address.
    * @param amount the amount of tokens that need to be transferred. 
    */
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert IncorrectAddress();

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance();
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}
