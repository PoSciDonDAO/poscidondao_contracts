// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

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
 */
contract Sci is ERC20Burnable, AccessControl {
    error CannotBeZeroAddress();

    /**
     * @dev Sets the values for {name} and {symbol} and initializes {treasuryWallet}
     * with the token distribution amount.
     * @param treasuryWallet_ address of the treasury wallet.
     */
    constructor(
        address treasuryWallet_,
        uint256 initialMintAmount_
    ) ERC20("PoSciDonDAO Token", "SCI") {
        if (treasuryWallet_ == address(0)) {
            revert CannotBeZeroAddress();
        }
        _mint(treasuryWallet_, initialMintAmount_ * (10 ** decimals()));
    }
}
