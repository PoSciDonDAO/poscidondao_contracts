// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

contract Donation is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error Unauthorized(address user);
    error InsufficientDonation();
    error InsufficientDeposit();
    error InsufficientBalance();
    error IncorrectAddress();
    error AccountBound();

    string  private _name;
    string  private _symbol;
    uint16  private _decimals;
    uint256 private _totalSupply;
    uint256 private _treshold;
    uint256 private _ratioEth;
    uint256 private _ratioUsdc;
    address private _govRes;
    address private _govOps;

    address public donationWallet;
    address public usdc;

    mapping(address => uint256) private _balances;
    mapping(address => uint256) public govs;
    mapping(address => uint256) public depositsGovRes;
    mapping(address => uint256) public depositsGovOps;

    modifier gov() {
        if(govs[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    event Rely(address indexed user);
    event Deny(address indexed user);
    event Push(address indexed user, address gov, uint256 amount);
    event Pull(address gov, address indexed user, uint256 amount);
    event DonationCompleted(address indexed user, uint256 donation, uint256 tokenAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(
        address _usdc,
        address _donationWallet
    ) {
        _name = "Donation Token";
        _symbol = "DON";
        _decimals = 18;
        usdc = _usdc;
        donationWallet = _donationWallet;

        govs[msg.sender] = 1;
    }
    
    //external functions

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
     * @dev returns the scientific research governance contract
     */
    function govRes() external view returns (address) {
        return _govRes;
    }

    /**
     * @dev returns the operations governance contract
     */
    function govOps() external view returns (address) {
        return _govOps;
    }

    /**
     * @dev sets the scientific research governance contract address
     * @param govRes_ the address of the scientific 
     * research governance contract
     */
    function setGovRes(address govRes_) external gov {
        _govRes = govRes_;
    }

    /**
     * @dev sets the operations governance contract address
     * @param govOps_ the address of the operations 
     * governance contract
     */
    function setGovOps(address govOps_) external gov {
        _govOps = govOps_;
    }

    /**
     * @dev adds a gov
     * @param user the user that becomes a gov
     */
    function addGov(address user) external gov {
        govs[user] = 1;
        emit Rely(user);
    }

    /**
     * @dev removes a gov
     * @param user the user that will be removed as a gov.
     */
    function removeGov(address user) external gov {
        if(govs[user] != 1) {
            revert Unauthorized(user);
        }
        delete govs[user];
        emit Deny(user);
    }

    /**
     * @dev sets the ratio of the ETH to DON token conversion 
     */
    function ratioEth(uint256 n, uint256 d) external gov {
        _ratioEth = 1000 * n / d;
    }

    /**
     * @dev sets the ratio of the USDC to DON token conversion 
     */
    function ratioUsdc(uint256 n, uint256 d) external gov {
        _ratioUsdc = 10 * n / d;
    }

    /**
     * @dev sets the treshold to donate usdc or eth
     * @param amount the least amount of tokens that needs be donated  
     */
    function setTreshold(uint256 amount) external gov {
        _treshold = amount;
    }

    /**
     * @dev sends Eth donations to the donation wallet, 
     * donor receives DON tokens.
     * ! Per 0.001 ETH --> 1 DON Token !
     * @param user the user that donates the Ether 
     */
    function donateEth(address user) external payable nonReentrant {
        //check if the donation treshold has been reached
        if (msg.value < _treshold) revert InsufficientDonation();

        //transfer Eth to donation wallet if successful
        (bool sent,) = donationWallet.call{value: msg.value}("");
        require(sent);
        
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
        //check if the donation treshold has been reached
        if (usdcAmount < _treshold) revert InsufficientDonation();

        //pull usdc from wallet to donation wallet
        IERC20(usdc).safeTransferFrom(user, donationWallet, usdcAmount);
        
        //calculate amount of don tokens 
        uint256 amount = usdcAmount * _ratioUsdc / 10;

        //mint don tokens to function caller
        _mint(user, amount);

        //emit event
        emit DonationCompleted(user, usdcAmount, amount);
    }

    /**
     * @dev pushes tokens from user to a gov contract
     * @param to gov contract
     * @param amount the amount of tokens that need to be pushed
     */
    function push(
        address user,
        address to,
        uint256 amount
    ) external returns (bool) {
        //check if governance contracts are selected
        if (to == _govRes) {
            //transfer from msg.sender to governance contract
            _transfer(user, _govRes, amount);

            //update GovRes deposits
            depositsGovRes[user] += amount;

            //emit Push event
            emit Push(user, _govRes, amount);
            return true; 

        } else if (to == _govOps) {
            //transfer from msg.sender to governance contract
            _transfer(user, _govOps, amount);

            //update GovOps deposits
            depositsGovOps[user] += amount;
            
            //emit Push event
            emit Push(user, _govOps, amount);
            return true;

        } else {

            revert AccountBound();
        }
    }
    
    /**
     * @dev transfers tokens from gov contract to msg.sender
     * @param from gov contract
     * @param amount the amount of tokens that need to be pulled
     */
    function pull(
        address from,
        address user,
        uint256 amount
    ) external returns (bool) {
        //check which gov contract tokens need to be pulled from
        if (from == _govRes) {
            //check if enough tokens have been deposited
            if (depositsGovRes[user] < amount) revert InsufficientDeposit();
            
            //transfer from gov contract to holder
            _transfer(_govRes, user, amount);
            
            //subtract the pulled amount
            depositsGovRes[user] -= amount;
            
            //emit Pull event
            emit Pull(_govRes, user, amount);
            return true; 

        } else if (from == _govOps) {
            //check which gov contract holds tokens
            if (depositsGovOps[user] < amount) revert InsufficientDeposit();
            
            //transfer from gov contract to holder
            _transfer(_govOps, user, amount);
            
            //subtract the pulled amount            
            depositsGovOps[user] -= amount;

            //emit Pull event
            emit Pull(_govRes, user, amount);
            return true;
            
        } else {
            revert AccountBound();
        }
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
