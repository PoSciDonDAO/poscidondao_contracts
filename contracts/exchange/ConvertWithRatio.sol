// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Copyright (c) 2024, PoSciDonDAO Foundation.
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero
 * General Public License as published by the Free Software Foundation, either version 3 of the License, or
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

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SCI Token Swap Contract
 * @dev Contract to exchange USDC, WETH, or ETH for SCI tokens at predefined rates.
 *      This contract handles the accounting of swapped tokens and enforces a cap on the maximum voucherAmount of SCI that can be swapped.
 */
contract ConvertWithRatio is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error NotWhitelisted();

    address private sci;
    address public voucher;
    address public admin;
    uint256 public conversionRate = 108057;
    //price of ETH given 1 ETH = 10500 vSCI = 3331,57
    //price at pinksale start: ~3600
    //ratio: 1.08057
    mapping(address => bool) public whitelist;

    event Converted(
        address indexed user,
        uint256 voucherAmount,
        uint256 sciAmount
    );

    event MembersWhitelisted(address[] members);
    event MembersUnwhitelisted(address[] members);

    modifier whitelisted() {
        if (!whitelist[msg.sender]) revert NotWhitelisted();
        _;
    }

    /**
     * @dev Initializes contract with addresses of tokens and treasury, initial swap rates, and whitelisted members.
     * @param admin_ The address of the treasury wallet where funds will be collected.
     * @param sci_ Address of the SCI token being swapped.
     * @param voucher_ Address of the USDC token acceptable for swaps.
     * @param whitelist_ The list of addresses to be added to the whitelist upon deployment.
     */
    constructor(
        address admin_,
        address sci_,
        address voucher_,
        address[] memory whitelist_
    ) {
        admin = admin_;
        sci = sci_;
        voucher = voucher_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        for (uint256 i = 0; i < whitelist_.length; i++) {
            whitelist[whitelist_[i]] = true;
        }
    }

    /**
     * @notice adds a member to the whitelist
     * @param members the address of the member that signed up for the whitelist
     */
    function addMembersToWhitelist(
        address[] memory members
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < members.length; i++) {
            whitelist[members[i]] = true;
        }
        emit MembersWhitelisted(members);
    }

    /**
     * @notice removes a member from the whitelist
     * @param members the address of the member to be removed from the whitelist
     */
    function removeMembersFromWhitelist(
        address[] memory members
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < members.length; i++) {
            whitelist[members[i]] = false;
        }
        emit MembersUnwhitelisted(members);
    }

    /**
     * @notice Handles the conversion of voucher SCI for 'real' SCI tokens.
     */
    function convertWithRatio() external nonReentrant whitelisted {
        uint256 voucherAmount = IERC20(voucher).balanceOf(msg.sender);
        uint256 sciAmount = (voucherAmount * conversionRate) / 100000;

        IERC20(voucher).safeTransferFrom(msg.sender, admin, voucherAmount);

        IERC20(sci).safeTransferFrom(admin, msg.sender, sciAmount);

        emit Converted(msg.sender, voucherAmount, sciAmount);
    }
}
