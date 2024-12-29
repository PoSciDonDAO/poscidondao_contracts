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

pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * @title Voucher Swap Contract
 * @dev Contract to exchange USDC, or ETH for Vouchers (vSCI tokens) at predefined rates.
 *      This contract handles the accounting of swapped tokens and enforces a cap on the maximum amount of vSCI that can be swapped.
 */
contract Swap is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    error CannotSwapAgain();
    error CannotSwapMoreThanHalfEther();
    error NotWhitelisted();
    error SaleExpired();
    error SoldOut();

    address public voucher;
    address public usdc;
    address public admin;

    uint256 public currentEtherPrice;
    uint256 public usdcLimit;
    uint256 public ethLimit;
    uint256 public priceInUsdc;
    uint256 public ethToVoucherConversionRate;
    uint256 public voucherSwapCap;
    uint256 public totVoucherSwapped;
    uint256 public deploymentTime;
    uint256 public end;
    uint256 public constant TOTAL_SUPPLY_VOUCHERS = 18910000e18;

    bool public whitelistActive = true;

    mapping(address => bool) public whitelist;
    mapping(address => bool) public hasSwapped;

    event MembersWhitelisted(address[] members);
    event MembersUnwhitelisted(address[] members);

    event Swapped(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 amountVoucher
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
     * @param voucher_ Address of the SCI token being swapped.
     * @param usdc_ Address of the USDC token acceptable for swaps.
     * @param membersWhitelist_ The list of addresses to be added to the whitelist upon deployment.
     */
    constructor(
        address admin_,
        address voucher_,
        address usdc_,
        address[] memory membersWhitelist_,
        uint256 currentEtherPrice_
    ) {
        admin = admin_;
        voucher = voucher_;
        usdc = usdc_;

        currentEtherPrice = currentEtherPrice_;
        priceInUsdc = 2115283; //0.2115283 USD per token
        usdcLimit = currentEtherPrice / 2 * 1e6;
        ethLimit = 0.5 ether; 
        ethToVoucherConversionRate = (currentEtherPrice_ * 1e7) / priceInUsdc;
        voucherSwapCap = (TOTAL_SUPPLY_VOUCHERS / 10000) * 50;

        deploymentTime = block.timestamp;
        end = deploymentTime + 3 days;

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
     * @notice sets the whitelist inactive
     */
    function setWhitelistInactive() external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistActive = false;
    }

    /**
     * @notice Sets the swap end timestamp.
     * @param endTimestamp The new end timestamp for the swap.
     */
    function setEnd(uint256 endTimestamp) public onlyRole(DEFAULT_ADMIN_ROLE) {
        end = endTimestamp;
    }

    /**
     * @notice Sets the swap limit for USDC.
     * @param newUsdcLimit The new limit in USDC
     */
    function setUsdcLimit(
        uint256 newUsdcLimit
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        usdcLimit = newUsdcLimit;
    }

    /**
     * @notice Sets the swap limit for ETH.
     * @param newEthLimit The new limit in ETH.
     */
    function setEthLimit(
        uint256 newEthLimit
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        priceInUsdc = newEthLimit;
    }
    /**
     * @notice Sets the swap rate for USDC.
     * @param newUsdcRate The new swap rate for USDC in terms of SCI tokens.
     */
    function setPriceInUsdc(
        uint256 newUsdcRate
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        priceInUsdc = newUsdcRate;
    }

    /**
     * @notice Sets the swap rate for ETH.
     * @param newEthToVoucherConversionRate The new swap rate for ETH in terms of SCI tokens.
     */
    function setEthToVoucherConversionRate(
        uint256 newEthToVoucherConversionRate
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        ethToVoucherConversionRate = newEthToVoucherConversionRate;
    }

    /**
     * @notice Sets the maximum cap for SCI tokens that can be swapped.
     * @param newVoucherSwapCap The new cap, expressed as a percentage of the total SCI supply.
     */
    function setVoucherSwapCap(
        uint256 newVoucherSwapCap
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        voucherSwapCap = (TOTAL_SUPPLY_VOUCHERS / 10000) * newVoucherSwapCap;
    }

    /**
     * @notice Handles the swap of USDC for SCI tokens.
     * @param amount The amount of USDC to swap.
     */
    function swapUsdc(
        uint256 amount
    ) external nonReentrant notExpired whitelisted {
        if (amount > usdcLimit)
            revert CannotSwapMoreThanHalfEther();
        if (hasSwapped[msg.sender]) revert CannotSwapAgain();
        uint256 voucherAmount = ((amount * 10000000) / priceInUsdc) * 1e12;

        if (totVoucherSwapped >= voucherSwapCap || voucherAmount > voucherSwapCap)
            revert SoldOut();

        IERC20(usdc).safeTransferFrom(msg.sender, admin, amount);

        IERC20(voucher).safeTransferFrom(admin, msg.sender, voucherAmount);

        totVoucherSwapped += voucherAmount;

        hasSwapped[msg.sender] = true;

        emit Swapped(msg.sender, address(usdc), amount, voucherAmount);
    }

    /**
     * @notice Handles the swap of ETH for SCI tokens.
     * @dev This function is payable and accepts ETH directly.
     */
    function swapEth() external payable nonReentrant notExpired whitelisted {
        if (msg.value > ethLimit) revert CannotSwapMoreThanHalfEther();
        if (hasSwapped[msg.sender]) revert CannotSwapAgain();
        uint256 voucherAmount = (msg.value * ethToVoucherConversionRate);

        if (totVoucherSwapped >= voucherSwapCap || voucherAmount > voucherSwapCap)
            revert SoldOut();

        (bool sent, ) = admin.call{value: msg.value}("");
        require(sent);

        IERC20(voucher).safeTransferFrom(admin, msg.sender, voucherAmount);

        totVoucherSwapped += voucherAmount;

        hasSwapped[msg.sender] = true;
        emit Swapped(msg.sender, address(0), msg.value, voucherAmount);
    }
}
