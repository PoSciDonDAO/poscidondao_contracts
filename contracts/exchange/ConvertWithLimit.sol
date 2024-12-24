// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SCI Token Swap Contract with Conversion Limits
 */
contract ConvertWithLimit is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error AlreadyConverted();
    error NotWhitelisted();

    address private sci;
    address public voucher;
    address public admin;

    mapping(address => bool) public whitelist;
    mapping(address => uint256) public conversionLimits;
    mapping(address => bool) public converted;

    event Converted(
        address indexed user,
        uint256 voucherAmount,
        uint256 sciAmount
    );

    event MembersWhitelisted(address[] members);
    event MembersUnwhitelisted(address[] members);
    event ConversionLimitsSet(address[] members, uint256[] limits);

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
     * @param limits_ The initial conversion limits for each whitelisted member.
     */
    constructor(
        address admin_,
        address sci_,
        address voucher_,
        address[] memory whitelist_,
        uint256[] memory limits_
    ) {
        require(whitelist_.length == limits_.length, "Mismatched input lengths");
        admin = admin_;
        sci = sci_;
        voucher = voucher_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        for (uint256 i = 0; i < whitelist_.length; i++) {
            whitelist[whitelist_[i]] = true;
            conversionLimits[whitelist_[i]] = limits_[i] * 1e18;
        }
    }

    /**
     * @notice Adds members to the whitelist with limits.
     * @param members The list of addresses to add.
     * @param limits The respective conversion limits for each address.
     */
    function setConversionLimits(
        address[] memory members,
        uint256[] memory limits
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(members.length == limits.length, "Mismatched input lengths");
        for (uint256 i = 0; i < members.length; i++) {
            whitelist[members[i]] = true;
            conversionLimits[members[i]] = limits[i];
        }
        emit ConversionLimitsSet(members, limits);
    }

    /**
     * @notice Removes members from the whitelist.
     * @param members The addresses of the members to remove.
     */
    function removeMembersFromWhitelist(
        address[] memory members
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < members.length; i++) {
            whitelist[members[i]] = false;
            conversionLimits[members[i]] = 0;
        }
        emit MembersUnwhitelisted(members);
    }

    /**
     * @notice Handles the conversion of voucher SCI for 'real' SCI tokens.
     */
    function convertWithLimit() external nonReentrant whitelisted {
        if (converted[msg.sender]) revert AlreadyConverted();

        uint256 voucherAmount = IERC20(voucher).balanceOf(msg.sender);
        uint256 limit = conversionLimits[msg.sender];
        uint256 amountToConvert = voucherAmount > limit ? limit : voucherAmount;

        IERC20(voucher).safeTransferFrom(msg.sender, admin, amountToConvert);
        IERC20(sci).safeTransferFrom(admin, msg.sender, amountToConvert);

        converted[msg.sender] = true;
        emit Converted(msg.sender, amountToConvert, amountToConvert);
    }
}
