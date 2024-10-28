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
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * @title SCI Token Swap Contract
 * @dev Contract to exchange USDC, WETH, or ETH for SCI tokens at predefined rates.
 *      This contract handles the accounting of swapped tokens and enforces a cap on the maximum amount of SCI that can be swapped.
 */
contract Swap is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    error CannotSwapAgain();
    error CannotSwapMoreThanOneEther();
    error NotWhitelisted();
    error SaleExpired();
    error SoldOut();

    address private sci;
    address public usdc;
    address public admin;

    uint256 public currentEtherPrice;
    uint256 public priceInUsdc;
    uint256 public ethToSciConversionRate;
    uint256 public sciSwapCap;
    uint256 public totSciSwapped;
    uint256 public deploymentTime;
    uint256 public end;
    uint256 public constant TOTAL_SUPPLY_SCI = 18910000e18;

    bool public whitelistActive = true;

    mapping(address => bool) public whitelist;
    mapping(address => bool) public hasSwapped;

    event SetNewAdmin(address indexed user, address indexed newAddress);
    event Swapped(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 amountSci
    );

    modifier notExpired() {
        if (block.timestamp > end) revert SaleExpired();
        _;
    }

    modifier whitelisted() {
        if (whitelistActive) {
            if (!whitelist[msg.sender]) revert NotWhitelisted();
        }
        _;
    }

    /**
     * @dev Initializes contract with addresses of tokens and treasury, initial swap rates, and whitelisted members.
     * @param admin_ The address of the treasury wallet where funds will be collected.
     * @param sci_ Address of the SCI token being swapped.
     * @param usdc_ Address of the USDC token acceptable for swaps.
     * @param membersWhitelist_ The list of addresses to be added to the whitelist upon deployment.
     */
    constructor(
        address admin_,
        address sci_,
        address usdc_,
        address[] memory membersWhitelist_,
        uint256 currentEtherPrice_
    ) {
        admin = admin_;
        sci = sci_;
        usdc = usdc_;

        currentEtherPrice = currentEtherPrice_;
        priceInUsdc = 2100;
        ethToSciConversionRate = currentEtherPrice * 10000 / priceInUsdc;
        sciSwapCap = (TOTAL_SUPPLY_SCI / 10000) * 50;

        deploymentTime = block.timestamp;
        end = block.timestamp + 3 days;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        for (uint256 i = 0; i < membersWhitelist_.length; i++) {
            whitelist[membersWhitelist_[i]] = true;
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
    }

    /**
     * @notice sets the whitelist inactive
     */
    function setWhitelistInactive() external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistActive = false;
    }

    /**
     * @notice Sets the swap end timestamp.
     * @param endTimestamp The new end timestamp for the swap.
     */
    function setEnd(uint256 endTimestamp) public {
        end = endTimestamp;
    }

    /**
     * @notice Sets the swap rate for USDC.
     * @param newUsdcRate The new swap rate for USDC in terms of SCI tokens.
     */
    function setpriceInUsdc(
        uint256 newUsdcRate
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        priceInUsdc = newUsdcRate;
    }

    /**
     * @notice Sets the swap rate for ETH.
     * @param newEthToSciConversionRate The new swap rate for ETH in terms of SCI tokens.
     */
    function setEthToSciConversionRate(
        uint256 newEthToSciConversionRate
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        ethToSciConversionRate = newEthToSciConversionRate;
    }

    /**
     * @notice Sets the maximum cap for SCI tokens that can be swapped.
     * @param newSciSwapCap The new cap, expressed as a percentage of the total SCI supply.
     */
    function setSciSwapCap(
        uint256 newSciSwapCap
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        sciSwapCap = (TOTAL_SUPPLY_SCI / 10000) * newSciSwapCap;
    }

    /**
     * @notice Handles the swap of USDC for SCI tokens.
     * @param amount The amount of USDC to swap.
     */
    function swapUsdc(
        uint256 amount
    ) external nonReentrant notExpired whitelisted {
        if (amount > currentEtherPrice * 1e6) revert CannotSwapMoreThanOneEther();
        if (hasSwapped[msg.sender]) revert CannotSwapAgain();
        uint256 sciAmount = ((amount * 10000) / priceInUsdc) * 1e12;

        if (totSciSwapped > sciSwapCap || sciAmount > sciSwapCap)
            revert SoldOut();

        IERC20(usdc).safeTransferFrom(msg.sender, admin, amount);

        IERC20(sci).safeTransferFrom(admin, msg.sender, sciAmount);

        totSciSwapped += sciAmount;

        hasSwapped[msg.sender] = true;

        emit Swapped(msg.sender, address(usdc), amount, sciAmount);
    }

    /**
     * @notice Handles the swap of ETH for SCI tokens.
     * @dev This function is payable and accepts ETH directly.
     */
    function swapEth() external payable nonReentrant notExpired whitelisted {
        if (msg.value > 1 ether) revert CannotSwapMoreThanOneEther();
        if (hasSwapped[msg.sender]) revert CannotSwapAgain();
        uint256 sciAmount = (msg.value * ethToSciConversionRate);
        if (totSciSwapped > sciSwapCap || sciAmount > sciSwapCap)
            revert SoldOut();

        (bool sent, ) = admin.call{value: msg.value}("");
        require(sent);

        IERC20(sci).safeTransferFrom(admin, msg.sender, sciAmount);

        totSciSwapped += sciAmount;

        hasSwapped[msg.sender] = true;
        emit Swapped(msg.sender, address(0), msg.value, sciAmount);
    }
}
