// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

/**
 * @title Participation Token (PO)
 * @dev A soulbound token contract for participation tokens. These tokens are mintable, burnable,
 * but not transferable, adhering to the soulbound token concept where tokens are permanently associated
 * with a wallet. Inherits ERC1155 for multi-token standard support and ERC1155Burnable for burn functionality.
 */
contract Po is ERC1155Burnable, AccessControl {
    error Frozen();
    error CannotBeZeroAddress();
    error Unauthorized(address user);

    address public admin;
    address public govOpsAddress;
    string public constant name = "Participation Token";
    string public constant symbol = "PO";
    bool internal _frozenUri = false;
    bool internal _frozenGovOps = false;
    string private _uri;
    uint256 private constant _PARTICIPATION_TOKEN_ID = 0;
    uint256 private _totalSupply;

    event Frozen(address indexed user, address indexed frozen);
    event GovOpsSet(address indexed user, address indexed newAddress);
    event TotalSupplyUpdated(uint256 oldSupply, uint256 newSupply);
    event UriSet(address indexed user, string indexed uri);

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory baseURI_, address admin_) ERC1155(baseURI_) {
        if (admin_ == address(0)) {
            revert CannotBeZeroAddress();
        }
        admin = admin_;
        _setURI(baseURI_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
    }

    /**
     * @dev Sets the governance operations address.
     * @param newGovOpsAddress Address of the new governance operations.
     */
    function setGovOps(
        address newGovOpsAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_frozenGovOps) revert Frozen();
        if (newGovOpsAddress == address(0)) revert CannotBeZeroAddress();
        if (govOpsAddress != address(0)) {
            _revokeRole(MINTER_ROLE, govOpsAddress);
        }

        govOpsAddress = newGovOpsAddress;
        _grantRole(MINTER_ROLE, govOpsAddress);
        emit GovOpsSet(msg.sender, newGovOps);
    }

    /**
     * @dev Updates the admin address and transfers admin role.
     * @param newAdmin The address to be set as the new admin.
     */
    function setAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert CannotBeZeroAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        emit AdminSet(oldAdmin, newAdmin);
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
        _frozenUri = true;
        Frozen(msg.sender, _frozenUri);
    }

    /**
     * @dev Freezes the governance operations address, preventing any further changes.
     */
    function freezeGovOps() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozenGovOps = true;
        Frozen(msg.sender, _frozenGovOps);
    }

    /**
     * @dev Mints a specified amount of participation tokens to a user.
     * @param user Address of the user to mint tokens to.
     * @param amount the amount of tokens to be minted
     */
    function mint(address user, uint256 amount) external onlyRole(MINTER_ROLE) {
        _totalSupply += amount;
        _mint(user, _PARTICIPATION_TOKEN_ID, amount, "");
        emit TotalSupplyUpdated(oldSupply, _totalSupply);
    }

    /**
     * @dev Mints a specified amount of participation tokens to a set of users by the admin.
     * @param amount Number of tokens to mint.
     */
    function mintBatch(
        address[] memory users,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) {
        _totalSupply += amount * users.length;

        for (uint256 i = 0; i < users.length; i++) {
            _mint(users[i], _PARTICIPATION_TOKEN_ID, amount, "");
        }
        emit TotalSupplyUpdated(oldSupply, _totalSupply);
    }

    /**
     * @dev Mints a specified amount of participation tokens to a user.
     */
    function burn(address account, uint256 id, uint256 value) public override {
        if (id != _PARTICIPATION_TOKEN_ID) {
            revert InvalidTokenId(id, _PARTICIPATION_TOKEN_ID);
        }
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _burn(account, id, value);
        _totalSupply -= value;
        emit TotalSupplyUpdated(oldSupply, _totalSupply);
    }

    /**
     * @dev Sets the base URI for constructing token-specific URIs. Can only be called by admin
     * and if the URI has not been frozen.
     * @param baseURI New base URI to set.
     */
    function setURI(
        string memory baseURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_frozenUri) revert Frozen();
        _setURI(baseURI);
        emit UriSet(msg.sender, baseURI);
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
        if (id != _PARTICIPATION_TOKEN_ID) {
            revert InvalidTokenId(id, _PARTICIPATION_TOKEN_ID);
        }
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
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] != _PARTICIPATION_TOKEN_ID) {
                revert InvalidTokenId(ids[i], _PARTICIPATION_TOKEN_ID);
            }
        }
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /**
     * @dev Generates a URI for a given token ID.
     * @return String representing the token URI.
     */
    function uri() public view returns (string memory) {
        return string(abi.encodePacked(_uri, "/", _PARTICIPATION_TOKEN_ID));
    }
}
