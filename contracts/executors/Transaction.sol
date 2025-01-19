// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title Transaction
 * @dev Executes DAO-supported transactions securely.
 */
contract Transaction is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error CannotBeZero();
    error CannotBeZeroAddress();
    error FactoryAlreadySet();
    error NotAContract(address);
    error Unauthorized(address user);

    address public constant USDC = 0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246; //replace with mainnet address
    address public constant SCI = 0xff88CC162A919bdd3F8552D331544629A6BEC1BE; //replace with mainnet address
    address public constant ADMIN = 0x96f67a852f8D3Bc05464C4F91F97aACE060e247A;

    address public governorExecutor;
    address public targetWallet;
    uint256 public amountUsdc;
    uint256 public amountSci;
    address public fundingWallet;
    address public factory;
    bool private _initialized;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    event ActionExecuted(address indexed action, string indexed contractName);
    event FactorySet(address indexed user, address newAddress);
    event Initialized(
        address fundingWallet,
        address targetWallet,
        uint256 amountUsdc,
        uint256 amountSci,
        address governorExecutor
    );

    /**
     * @dev Constructor that grants DEFAULT_ADMIN_ROLE to ADMIN address
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, ADMIN);
    }

    /**
     * @dev Initializes the transaction with required parameters
     * @param params Encoded parameters (fundingWallet, targetWallet, amountUsdc, amountSci, governorExecutor)
     */
    function initialize(bytes memory params) external {
        if (_initialized) revert AlreadyInitialized();
        if (msg.sender != factory) revert Unauthorized(msg.sender);

        (address fundingWallet_, address targetWallet_, uint256 amountUsdc_, uint256 amountSci_, address governorExecutor_) = 
            abi.decode(params, (address, address, uint256, uint256, address));

        if (
            fundingWallet_ == address(0) ||
            targetWallet_ == address(0) ||
            governorExecutor_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }

        if (amountUsdc_ == 0 && amountSci_ == 0) {
            revert CannotBeZero();
        }

        targetWallet = targetWallet_;
        amountUsdc = amountUsdc_;
        amountSci = amountSci_;
        fundingWallet = fundingWallet_;
        governorExecutor = governorExecutor_;
        _grantRole(GOVERNOR_ROLE, governorExecutor_);
        _initialized = true;
        emit Initialized(fundingWallet_, targetWallet_, amountUsdc_, amountSci_, governorExecutor_);
    }

    /**
     * @dev Sets the new factory contract address for Transaction
     * @param newFactory The address to be set as the factory contract
     */
    function setFactory(
        address newFactory
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFactory == address(0)) revert CannotBeZeroAddress();
        if (factory != address(0)) revert FactoryAlreadySet();
        uint256 size;
        assembly {
            size := extcodesize(newFactory)
        }
        if (size == 0) revert NotAContract(newFactory);

        factory = newFactory;
        emit FactorySet(msg.sender, newFactory);
    }

    /**
     * @dev Execute the proposal using ERC20 tokens (USDC or SCI)
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        if (amountUsdc > 0) {
            _transferToken(USDC, fundingWallet, targetWallet, amountUsdc);
        }
        if (amountSci > 0) {
            _transferToken(SCI, fundingWallet, targetWallet, amountSci);
        }
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
        emit ActionExecuted(address(this), "Transaction");
    }

    /**
     * @dev Internal function to handle token transfers
     * @param token The ERC20 token to transfer
     * @param from The address to transfer tokens from
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     */
    function _transferToken(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
