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
 * @dev Contract to exchange USDC, WETH, or MATIC for SCI tokens at predefined rates.
 *      This contract handles the accounting of swapped tokens and enforces a cap on the maximum amount of SCI that can be swapped.
 */
contract Swap is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error SaleExpired();
    error SoldOut();

    address private sci;
    address public usdc;
    address public weth;
    address public treasuryWallet;

    uint256 public rateUsdc;
    uint256 public rateMatic;
    uint256 public rateWeth;
    uint256 public sciSwapCap;
    uint256 public totSciSwapped;
    uint256 public deploymentTime;
    uint256 public end;

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
     * @param weth_ Address of the WETH token acceptable for swaps.
     */
    constructor(
        address treasuryWallet_,
        address sci_,
        address usdc_,
        address weth_
    ) {
        treasuryWallet = treasuryWallet_;
        sci = sci_;
        usdc = usdc_;
        weth = weth_;

        rateUsdc = 2100;
        rateMatic = 3000;
        rateWeth = 14762;
        sciSwapCap = (IERC20(sci).totalSupply() / 10000) * 50;
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);

        deploymentTime = block.timestamp;
        end = block.timestamp + 3 days;
    }


    function setEnd(uint256 endTimestamp) public {
        end = endTimestamp;
    }

    /**
     * @notice Sets the swap rate for USDC.
     * @param _rateUsdc The new swap rate for USDC in terms of SCI tokens.
     */
    function setRateUsdc(
        uint256 _rateUsdc
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        rateUsdc = _rateUsdc;
    }

    /**
     * @notice Sets the swap rate for MATIC.
     * @param _rateMatic The new swap rate for MATIC in terms of SCI tokens.
     */
    function setRateMatic(
        uint256 _rateMatic
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        rateMatic = _rateMatic;
    }

    /**
     * @notice Sets the swap rate for WETH.
     * @param _rateWeth The new swap rate for WETH in terms of SCI tokens.
     */
    function setRateWeth(
        uint256 _rateWeth
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        rateWeth = _rateWeth;
    }

    /**
     * @notice Sets the maximum cap for SCI tokens that can be swapped.
     * @param _sciSwapCap The new cap, expressed as a percentage of the total SCI supply.
     */
    function setSciSwapCap(
        uint256 _sciSwapCap
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        sciSwapCap = (IERC20(sci).totalSupply() / 10000) * _sciSwapCap;
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
     * @notice Handles the swap of WETH for SCI tokens.
     * @param amount The amount of WETH to swap.
     */
    function swapWeth(uint256 amount) external nonReentrant notExpired {
        if (totSciSwapped == sciSwapCap) revert SoldOut();
        IERC20(weth).safeTransferFrom(msg.sender, treasuryWallet, amount);
        uint256 sciAmount = amount * rateWeth;
        IERC20(sci).safeTransferFrom(treasuryWallet, msg.sender, sciAmount);
        totSciSwapped += sciAmount;
        emit Swapped(msg.sender, address(weth), amount, sciAmount);
    }

    /**
     * @notice Handles the swap of MATIC for SCI tokens.
     * @dev This function is payable and accepts MATIC directly.
     */
    function swapMatic() external payable nonReentrant notExpired {
        if (totSciSwapped == sciSwapCap) revert SoldOut();
        (bool sent, ) = treasuryWallet.call{value: msg.value}("");
        require(sent);
        uint256 sciAmount = (msg.value * 10000 / rateMatic);
        IERC20(sci).safeTransferFrom(treasuryWallet, msg.sender, sciAmount);
        totSciSwapped += sciAmount;
        emit Swapped(msg.sender, address(0), msg.value, sciAmount);
    }
}
