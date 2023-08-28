// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Trading is ERC20Capped {
    error Unauthorized(address user);
    error SellFeeTooHigh();

    uint8 lLBA;
    address treasuryWallet;

    mapping(address => uint256) public routerAddresses;
    mapping(address => uint256) public wards;

    modifier dao() {
        if(wards[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    enum TransferType { Move, Buy, Sell }

    uint64 public fee;

    event Rely(address indexed user);
    event Deny(address indexed user);
    
    constructor(
        address _treasuryWallet
    ) 
    ERC20("Trading Token", "SCI") ERC20Capped(18910000e18) {
        treasuryWallet = _treasuryWallet;

        _mint(treasuryWallet, cap());
        
        wards[msg.sender] = 1;
    }

    /**
     * @dev set LLBA to finalized;
     */
    function setLLBAToCompleted() public dao {
        lLBA = 1;
    }

    /**
     * @dev adds a gov
     * @param user the user that becomes a gov
     */
    function addGov(address user) external dao {
        wards[user] = 1;
        emit Rely(user);
    }

    /**
     * @dev removes a gov
     * @param user the user that will be removed as a gov.
     */
    function removeGov(address user) external dao {
        if(wards[user] != 1) {
            revert Unauthorized(user);
        }
        delete wards[user];
        emit Deny(user);
    }

    function setFee(uint64 _fee) external dao {
        if ((_fee/1e4) > 10) revert SellFeeTooHigh();
        fee = _fee;
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
    ) internal returns (bool) {

        TransferType transferType;

        uint256 _transferFee;
        (transferType, _transferFee) = getTransferType(from, to);

        if(_transferFee > 0) {
            uint256 _calcFee = (amount * _transferFee) / (1e7);
            _transfer(from, treasuryWallet, _calcFee);

            amount -= _calcFee;
        }

        _transfer(from, to, amount);
        return true;
    }

    function getTransferType(
        address from, 
        address to
    ) internal view returns (TransferType, uint64) {
        if(routerAddresses[from] == 1) {
            return (TransferType.Buy, 0);
        } else if (routerAddresses[to] == 1) {
            return (TransferType.Sell, fee);
        } else {
            return (TransferType.Move, 0);
        }
    }

    function setRouterAddress(
        address _router
    ) external dao {
        routerAddresses[_router] = 1;
    }

    function removeRouterAddress(
        address _oldRouter
    ) external dao {
        delete routerAddresses[_oldRouter];
    }
}