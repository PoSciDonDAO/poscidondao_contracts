// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
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
contract Sci is ERC20Burnable, AccessControl {
    // Treasury wallet address that receives initial mint and can mint additional tokens.
    address public treasuryWallet;
    
    /**
     * @dev Sets the values for {name} and {symbol}, initializes {treasuryWallet} 
     * with the token distribution amount, and grants default admin role.
     * @param _treasuryWallet address of the treasury wallet.
     */
    constructor(address _treasuryWallet) ERC20("PoSciDonDAO", "SCI") {
        treasuryWallet = _treasuryWallet;
        _grantRole(DEFAULT_ADMIN_ROLE, _treasuryWallet);
        _mint(_treasuryWallet, 18910000 * (10 ** decimals()));
    }

    /**
     * @dev Mints `amount` tokens to the specified `account`.
     * Can only be called by the account with the DEFAULT_ADMIN_ROLE.
     *
     * Requirements:
     * - the caller must have the `DEFAULT_ADMIN_ROLE`.
     *
     * @param account The address of the account to mint tokens to.
     * @param amount The number of tokens to be minted.
     */
    function mint(
        address account,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(account, amount);
    }
}
