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
    error Unauthorized(address user);

    address public immutable usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public immutable sci = 0x25E0A7767d03461EaF88b47cd9853722Fe05DFD3;
    address public immutable admin = 0x96f67a852f8D3Bc05464C4F91F97aACE060e247A;

    address public governorExecutor;
    address public targetWallet;
    uint256 public amountUsdc;
    uint256 public amountSci;
    address public fundingWallet;
    bool private _initialized;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    event ActionExecuted(address indexed action, string indexed contractName);
    event Initialized(
        address fundingWallet,
        address targetWallet,
        uint256 amountUsdc,
        uint256 amountSci,
        address governorExecutor
    );

    /**
     * @dev Constructor that grants DEFAULT_ADMIN_ROLE to admin address
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @dev Initializes the transaction with required parameters
     * @param params Encoded parameters (fundingWallet, targetWallet, amountUsdc, amountSci, governorExecutor)
     */
    function initialize(bytes memory params) external {
        if (_initialized) revert AlreadyInitialized();

        (
            address fundingWallet_,
            address targetWallet_,
            uint256 amountUsdc_,
            uint256 amountSci_,
            address governorExecutor_
        ) = abi.decode(params, (address, address, uint256, uint256, address));

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
        emit Initialized(
            fundingWallet_,
            targetWallet_,
            amountUsdc_,
            amountSci_,
            governorExecutor_
        );
    }

    /**
     * @dev Execute the proposal using ERC20 tokens (usdc or sci)
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        if (amountUsdc > 0) {
            _transferToken(usdc, fundingWallet, targetWallet, amountUsdc);
        }
        if (amountSci > 0) {
            _transferToken(sci, fundingWallet, targetWallet, amountSci);
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
