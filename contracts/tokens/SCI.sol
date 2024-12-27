// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Copyright (c) 2024, PoSciDonDAO Foundation.
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero
 * General Public License (AGPL) as published by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
 * implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License along with this program. If not,
 * see <http://www.gnu.org/licenses/>.
 */

pragma solidity 0.8.28;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

// ███████╗ ██████╗██╗
// ██╔════╝██╔════╝██║
// ███████╗██║     ██║
// ╚════██║██║     ██║
// ███████║╚██████╗██║
// ╚══════╝ ╚═════╝╚═╝

/**
 * @dev Implementation of SCI, PoSciDonDAO's ERC20 Token. 
 * Token address: 0x25E0A7767d03461EaF88b47cd9853722Fe05DFD3
 */
contract Sci is ERC20Burnable, AccessControl {
    error CannotBeZeroAddress();

    /**
     * @dev Initializes the token with the specified {name} and {symbol}, 
     * and mints the initial token distribution to the {treasuryWallet}.
     * @param treasuryWallet_ The address of the treasury wallet.
     * @param initialMintAmount_ The initial number of tokens to mint.
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
