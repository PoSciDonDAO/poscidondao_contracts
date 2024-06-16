// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

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
    error Unauthorized(address user);

    ///*** STORAGE ***///
    address public treasuryWallet;
    address public govOpsAddress;

    ///*** MODIFIER ***///
    modifier onlyGov() {
        if (!(msg.sender == govOpsAddress)) revert Unauthorized(msg.sender);
        _;
    }

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {treasuryWallet}
     * with the token distribution amount, and grants default admin role.
     * @param treasuryWallet_ address of the treasury wallet.
     */
    constructor(address treasuryWallet_) ERC20("PoSciDonDAO Token", "SCI") {
        treasuryWallet = treasuryWallet_;
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
        _mint(treasuryWallet_, 4538400 * (10 ** decimals()));
    }

    /**
     * @dev sets the GovernorOperations contract address
     */
    function setGovOps(
        address newGovOpsAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govOpsAddress = newGovOpsAddress;
    }

    /**
     * @dev Mints `amount` tokens to the specified `account`.
     * Can only be called by the GovernorOperations smart contract.
     *
     * @param amount The number of tokens to be minted.
     */
    function mint(uint256 amount) external onlyGov {
        _mint(treasuryWallet, amount);
    }
}
