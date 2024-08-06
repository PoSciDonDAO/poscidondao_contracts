// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../../contracts/interface/ISci.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

// ███████╗ ██████╗██╗
// ██╔════╝██╔════╝██║
// ███████╗██║     ██║
// ╚════██║██║     ██║
// ███████║╚██████╗██║
// ╚══════╝ ╚═════╝╚═╝

/**
 * @title SCI
 * @dev Implementation of SCI, PoSciDonDAO's ERC20 Token.
 * This contract handles token minting, burning, and role-based permissions.
 */
contract Sci is ISci, ERC20Burnable, AccessControl {
    error CannotBeZeroAddress();
    error Unauthorized(address user);

    ///*** STORAGE ***///
    address public treasuryWallet;
    address public govOpsAddress;

    ///*** EVENT ***///
    event SetNewGovOps(address indexed user, address indexed newAddress);
    event SetNewTreasuryWallet(
        address indexed user,
        address indexed newAddress
    );

    ///*** MODIFIER ***///
    modifier onlyGovOps() {
        if (!(msg.sender == govOpsAddress)) revert Unauthorized(msg.sender);
        _;
    }

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {treasuryWallet}
     * with the token distribution amount, and grants default admin role.
     * @param treasuryWallet_ address of the treasury wallet.
     */
    constructor(
        address treasuryWallet_,
        uint256 initialMintAmount_
    ) ERC20("PoSciDonDAO Token", "SCI") {
        if (treasuryWallet_ == address(0)) {
            revert CannotBeZeroAddress();
        }
        treasuryWallet = treasuryWallet_;
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
        _mint(treasuryWallet_, initialMintAmount_ * (10 ** decimals()));
    }

    /**
     * @dev Updates the treasury wallet address and transfers admin role.
     * @param newTreasuryWallet The address to be set as the new treasury wallet.
     */
    function setTreasuryWallet(
        address newTreasuryWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldTreasuryWallet = treasuryWallet;
        treasuryWallet = newTreasuryWallet;
        _grantRole(DEFAULT_ADMIN_ROLE, newTreasuryWallet);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldTreasuryWallet);
        emit SetNewTreasuryWallet(oldTreasuryWallet, newTreasuryWallet);
    }

    /**
     * @dev sets the GovernorOperations (GovOps) contract address
     * @param newGovOpsAddress The new address of the GovernorOperations (GovOps) contract.
     */
    function setGovOps(
        address newGovOpsAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovOpsAddress == address(0)) {
            revert CannotBeZeroAddress();
        }
        govOpsAddress = newGovOpsAddress;
        emit SetNewGovOps(msg.sender, newGovOpsAddress);
    }

    /**
     * @dev Mints `amount` tokens to the specified `account`.
     * Can only be called by the GovernorOperations (GovOps) smart contract.
     *
     * @param amount The number of tokens to be minted.
     */
    function mint(uint256 amount) external onlyGovOps {
        _mint(treasuryWallet, amount);
    }
}
