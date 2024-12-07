// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

/**
 * @title Donation Token (DON)
 * @dev A soulbound token contract for participation tokens. These tokens are mintable, burnable,
 * but not transferable, adhering to the soulbound token concept where tokens are permanently associated
 * with a wallet. Inherits ERC1155 for multi-token standard support and ERC1155Burnable for burn functionality.
 */
contract Don is ERC1155Burnable, AccessControl {
    error Frozen();
    error Unauthorized(address user);

    address public admin; 
    address public donationAddress;
    string public name = "Donation Token";
    string public symbol = "DON";
    bool internal frozenUri = false;
    bool internal frozenDonation = true; 
    string private _uri;
    uint256 private constant DONATION_TOKEN_ID = 0;
    uint256 private _totalSupply;

    /**
     * @dev Modifier to restrict actions to the Governance Operations address.
     */
    modifier onlyDonation() {
        if (msg.sender != donationAddress) revert Unauthorized(msg.sender);
        _;
    }

    constructor(
        string memory baseURI_,
        address treasuryWallet_
    ) ERC1155(baseURI_) {
        admin = treasuryWallet_;
        _setURI(baseURI_);
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
    }

    /**
     * @dev Sets the governance operations address.
     * @param newDonationAddress Address of the new governance operations.
     */
    function setDonation(
        address newDonationAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (frozenDonation) revert Frozen();
        donationAddress = newDonationAddress;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Freezes the base URI, preventing any further changes.
     */
    function freezeUri() external onlyRole(DEFAULT_ADMIN_ROLE) {
        frozenUri = true;
    }

    /**
     * @dev Freezes the governance operations address, preventing any further changes.
     */
    function freezeDonation() external onlyRole(DEFAULT_ADMIN_ROLE) {
        frozenDonation = true;
    }

    /**
     * @dev Mints a specified amount of participation tokens to a user.
     * @param user Address of the user to mint tokens to.
     * @param amount the amount of tokens to be minted
     */
    function mint(address user, uint256 amount) external onlyDonation {
        _mint(user, DONATION_TOKEN_ID, amount, "");
        _totalSupply += amount;
    }

    /**
     * @dev Mints a specified amount of participation tokens to a set of users by the admin.
     * @param amount Number of tokens to mint.
     */
    function mintBatchByAdmin(address[] memory users, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < users.length; i++) {
            _mint(users[i], DONATION_TOKEN_ID, amount, "");
            _totalSupply += amount;
        }
    }

    /**
     * @dev Mints a specified amount of participation tokens to a user.
     */
    function burn(address account, uint256 id, uint256 value) public override {
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _burn(account, id, value);
        _totalSupply -= value;
    }

    /**
     * @dev Sets the base URI for constructing token-specific URIs. Can only be called by admin
     * and if the URI has not been frozen.
     * @param baseURI New base URI to set.
     */
    function setURI(
        string memory baseURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (frozenUri) revert Frozen();
        _setURI(baseURI);
    }

    /**
     * @dev Overrides supportsInterface to integrate IERC1155, IERC1155MetadataURI, and ERC1155Burnable interfaces.
     * @param interfaceId Interface identifier to query support of.
     * @return True if the contract supports the queried interface.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            interfaceId == type(ERC1155Burnable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Allows token transfers only if the sender has the DEFAULT_ADMIN_ROLE.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        super.safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @dev Allows batch token transfers only if the sender has the DEFAULT_ADMIN_ROLE.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /**
     * @dev Generates a URI for a given token ID.
     * @return String representing the token URI.
     */
    function uri() public view returns (string memory) {
        return string(abi.encodePacked(_uri, "/", DONATION_TOKEN_ID));
    }
}
