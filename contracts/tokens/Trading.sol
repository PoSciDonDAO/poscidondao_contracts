// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Trading is ERC20Capped {
    error Unauthorized(address user);
    error SellFeeTooHigh();

    uint8 lLBA;
    address donationWallet;
    address treasuryWallet;

    mapping(address => uint256) public routerAddresses;
    mapping(address => uint256) public govs;

    modifier gov() {
        if(govs[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    enum TransferType { Move, Buy, Sell }

    struct Fees {
        uint64 treasuryFee;
        uint64 donationFee;
    }

    Fees public fees;
    Fees public noFees;

    event Rely(address indexed user);
    event Deny(address indexed user);
    
    constructor(
        address _donationWallet,
        address _treasuryWallet
    ) 
    ERC20("Trading Token", "SCI") ERC20Capped(18910000e18) {
        donationWallet = _donationWallet;
        treasuryWallet = _treasuryWallet;

        _mint(treasuryWallet, cap());

        govs[msg.sender] = 1;
    }

    /**
     * @dev set LLBA to finalized;
     */
    function setLLBAToCompleted() public gov {
        lLBA = 1;
    }

    /**
     * @dev adds a gov
     * @param user the user that becomes a gov
     */
    function addGov(address user) public gov {
        govs[user] = 1;
        emit Rely(user);
    }

    /**
     * @dev removes a gov
     * @param user the user that will be removed as a gov.
     */
    function removeGov(address user) public gov {
        if(govs[user] != 1) {
            revert Unauthorized(user);
        }
        delete govs[user];
        emit Deny(user);
    }

    function setFees(uint64 donationFee, uint64 treasuryFee) public gov {
        if ((donationFee + treasuryFee)/1e4 > 10) revert SellFeeTooHigh();
        fees.donationFee = donationFee;
        fees.treasuryFee = treasuryFee;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        if (lLBA == 1) {
            return _transferTokens(from, to, amount);
        } else {
            _transfer(from, to, amount);
            return true;
        }
    }

    function transfer(
        address to, 
        uint256 amount
    ) public override returns (bool) {
        address owner = _msgSender();
        if (lLBA == 1) {
            _transferTokens(owner, to, amount);
        } else {
            _transfer(owner, to, amount);
        }
        return true;
    }

    function _transferTokens(
        address from, 
        address to, 
        uint256 amount
    ) internal returns(bool) {

        TransferType transferType;
        Fees memory transferFees; 

        (transferType, transferFees) = getTransferType(from, to);

        if(transferFees.treasuryFee + transferFees.donationFee != 0) {
            uint256 donationFee = (amount * transferFees.donationFee) / (1e7);
            _transfer(from, treasuryWallet, donationFee);
            uint256 treasuryFee = (amount * transferFees.treasuryFee) / (1e7);
            _transfer(from, donationWallet, treasuryFee);

            amount -= donationFee;
            amount -= treasuryFee;
        }

        _transfer(from, to, amount);
        return true;
    }

    function getTransferType(
        address from, 
        address to
    ) internal view returns (TransferType, Fees memory) {
        if(routerAddresses[from] == 1) {
            return (TransferType.Buy, noFees);
        } else if (routerAddresses[to] == 1) {
            return (TransferType.Sell, fees);
        } else {
            return (TransferType.Move, noFees);
        }
    }

    function setRouterAddress(
        address router
    ) external gov {
        routerAddresses[router] = 1;
    }
}