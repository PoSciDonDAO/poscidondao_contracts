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

    error SaleExpired();
    error SoldOut();

    address private sci;
    address public usdc;
    address public treasuryWallet;

    uint256 public rateUsdc;
    uint256 public rateEth;
    uint256 public sciSwapCap;
    uint256 public totSciSwapped;
    uint256 public deploymentTime;
    uint256 public end;
    uint256 public constant TOTAL_SUPPLY_SCI = 18910000e18;

    event Swapped(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 amountSci
    );

    modifier notExpired() {
        if(block.timestamp > deploymentTime + end) revert SaleExpired();
        _;
    }

    /**
     * @dev Initializes contract with addresses of tokens and treasury, and initial swap rates.
     * @param treasuryWallet_ The address of the treasury wallet where funds will be collected.
     * @param sci_ Address of the SCI token being swapped.
     * @param usdc_ Address of the USDC token acceptable for swaps.
     */
    constructor(
        address treasuryWallet_,
        address sci_,
        address usdc_
    ) {
        treasuryWallet = treasuryWallet_;
        sci = sci_;
        usdc = usdc_;

        rateUsdc = 2100;
        rateEth = 14762;
        sciSwapCap = ( TOTAL_SUPPLY_SCI / 10000) * 50;
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);

        deploymentTime = block.timestamp;
        end = block.timestamp + 3 days;
    }

    /**
     * @notice Sets the swap rate for USDC.
     * @param endTimestamp The new swap rate for USDC in terms of SCI tokens.
     */
    function setEnd(uint256 endTimestamp) public {
        end = endTimestamp;
    }

    /**
     * @notice Sets the swap rate for USDC.
     * @param newUsdcRate The new swap rate for USDC in terms of SCI tokens.
     */
    function setRateUsdc(
        uint256 newUsdcRate
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        rateUsdc = newUsdcRate;
    }

    /**
     * @notice Sets the swap rate for ETH.
     * @param newEthRate The new swap rate for ETH in terms of SCI tokens.
     */
    function setRateEth(
        uint256 newEthRate
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        rateEth = newEthRate;
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
    function swapUsdc(uint256 amount) external nonReentrant notExpired {
        if (totSciSwapped == sciSwapCap) revert SoldOut();
        IERC20(usdc).safeTransferFrom(msg.sender, treasuryWallet, amount);
        uint256 sciAmount = (amount * 10000 / rateUsdc) * 1e12;
        IERC20(sci).safeTransferFrom(treasuryWallet, msg.sender, sciAmount);
        totSciSwapped += sciAmount;
        emit Swapped(msg.sender, address(usdc), amount, sciAmount);
    }

    /**
     * @notice Handles the swap of ETH for SCI tokens.
     * @dev This function is payable and accepts ETH directly.
     */
    function swapEth() external payable nonReentrant notExpired {
        if (totSciSwapped == sciSwapCap) revert SoldOut();
        (bool sent, ) = treasuryWallet.call{value: msg.value}("");
        require(sent);
        uint256 sciAmount = (msg.value * rateEth);
        IERC20(sci).safeTransferFrom(treasuryWallet, msg.sender, sciAmount);
        totSciSwapped += sciAmount;
        emit Swapped(msg.sender, address(0), msg.value, sciAmount);
    }
}
