// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "contracts/interface/IDonation.sol";

contract Donation is IDonation, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    error AccountBound();
    error IncorrectAddress();
    error InsufficientBalance();
    error InsufficientDonation();
    error InsufficientStake();
    error Unauthorized(address user);

    string  private _name;
    string  private _symbol;
    uint16  private _decimals;
    uint256 private _totalSupply;
    uint256 private _donationThreshold;
    uint256 private _ratioEth;
    uint256 private _ratioUsdc;
    address private _stakingContract;

    address public donationWallet;
    address public usdc;

    mapping(address => uint256) private _balances;
    mapping(address => uint256) public wards;
    mapping(address => uint256) public stake;

    modifier gov() {
        if(wards[msg.sender] != 1) revert Unauthorized(msg.sender);
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
        address _donationWallet
    ) {
        _name = "Donation Token";
        _symbol = "DON";
        _decimals = 18;
        usdc = _usdc;
        donationWallet = _donationWallet;

        wards[msg.sender] = 1;
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
    function balanceOf(address _account) external view returns (uint256) {
        return _balances[_account];
    }

    /**
     * @dev returns the staking contract
     */
    function stakingContract() external view returns (address) {
        return _stakingContract;
    }

    /**
     * @dev sets the staking contract address
     * @param stakingContract_ the address of the staking contract
     */
    function setStakingContract(address stakingContract_) external gov {
        _stakingContract = stakingContract_;
    }

    /**
     * @dev adds a gov
     * @param _user the user that becomes a gov
     */
    function addGov(address _user) external gov {
        wards[_user] = 1;
        emit Rely(_user);
    }

    /**
     * @dev removes a gov
     * @param _user the user that will be removed as a gov.
     */
    function removeGov(address _user) external gov {
        if(wards[_user] != 1) {
            revert Unauthorized(_user);
        }
        delete wards[_user];
        emit Deny(_user);
    }

    /**
     * @dev sets the ratio of the ETH to DON token conversion 
     */
    function setRatioEth(uint256 _n, uint256 _d) external gov {
        _ratioEth = 1000 * _n / _d;
    }

    /**
     * @dev sets the ratio of the USDC to DON token conversion 
     */
    function setRatioUsdc(uint256 _n, uint256 _d) external gov {
        _ratioUsdc = 10 * _n / _d;
    }

    /**
     * @dev sets the Threshold to donate usdc or eth
     * @param _amount the least amount of tokens that needs be donated  
     */
    function setDonationThreshold(uint256 _amount) external gov {
        _donationThreshold = _amount;
    }

    /**
     * @dev sends Eth donations to the donation wallet, 
     * donor receives DON tokens.
     * ! Per 0.001 ETH --> 1 DON Token !
     * @param _user the user that donates the Ether 
     */
    function donateEth(address _user) external payable nonReentrant {
        //check if the donation Threshold has been reached
        if (msg.value < _donationThreshold) revert InsufficientDonation();

        //transfer Eth to donation wallet if successful
        (bool sent,) = donationWallet.call{value: msg.value}("");
        require(sent);
        
        //determine the amount of DON tokens issued
        uint256 _amount = msg.value * _ratioEth;

        //mint DON tokens
        _mint(_user, _amount);

        //emit event
        emit DonationCompleted(_user, msg.value, _amount);
    }

    /**
     * @dev sends donated USDC to the donation wallet 
     * donor receives DON tokens based on the given ratio.
     * @param _usdcAmount the amount of donated USDC
     * @param _user the user that donates the USDC  
     */
    function donateUsdc(address _user, uint256 _usdcAmount) external nonReentrant {
        //check if the donation Threshold has been reached
        if (_usdcAmount < _donationThreshold) revert InsufficientDonation();

        //pull usdc from wallet to donation wallet
        IERC20(usdc).safeTransferFrom(_user, donationWallet, _usdcAmount);
        
        //calculate amount of don tokens 
        uint256 _amount = _usdcAmount * _ratioUsdc / 10;

        //mint don tokens to function caller
        _mint(_user, _amount);

        //emit event
        emit DonationCompleted(_user, _usdcAmount, _amount);
    }

    /**
     * @dev pushes tokens from user to the staking contract
     * @param _user the user that wants to push their DON tokens
     * @param _amount the amount of tokens that need to be pushed
     */
    function push(
        address _user,
        uint256 _amount
    ) external nonReentrant {

        //transfer from user to governance contract
        _transfer(_user, _stakingContract, _amount);

        //update staked amount
        stake[_user] += _amount;

        //emit Push event
        emit Push(_user, _amount);
    }
    
    /**
     * @dev transfers tokens from gov contract to msg.sender
     * @param _user the user that wants to pull their DON tokens
     * @param _amount the amount of tokens that need to be pulled
     */
    function pull(
        address _user,
        uint256 _amount
    ) external nonReentrant {
        if (stake[_user] < _amount) revert InsufficientStake();
        
        //transfer from staking contract to holder
        _transfer(_stakingContract, _user, _amount);
        
        //subtract the pulled amount            
        stake[_user] -= _amount;

        //emit Pull event
        emit Pull(_user, _amount);
    }

    /**
     * @dev allows you to burn your DON tokens
     * @param _amount of tokens that will be burned
     */
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    } 

    //internal functions
    /**
     * @dev mints DON tokens
     * @param _account account of the donor
     * @param _amount amount of DON tokens that will be minted
     */
    function _mint(address _account, uint256 _amount) internal {
        if (_account == address(0)) revert IncorrectAddress();

        _beforeTokenTransfer(address(0), _account, _amount);

        _totalSupply += _amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[_account] += _amount;
        }
        emit Transfer(address(0), _account, _amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     * @param _account account of the donor
     * @param _amount amount of DON tokens that will be burned
     */
    function _burn(address _account, uint256 _amount) internal virtual {
        if (_account == address(0)) revert IncorrectAddress();

        _beforeTokenTransfer(_account, address(0), _amount);

        uint256 accountBalance = _balances[_account];
        if (accountBalance < _amount) revert InsufficientBalance();
        unchecked {
            _balances[_account] = accountBalance - _amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= _amount;
        }

        emit Transfer(_account, address(0), _amount);
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
