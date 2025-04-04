// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

/**
 * @title Participation Token (PO)
 * @dev A soulbound token ERC1155 contract for participation tokens. These tokens are mintable, burnable,
 * but not transferable (only admin can transfer), adhering to the soulbound token concept where tokens are permanently associated
 * with a wallet. Can only mint one token id (0). ERC1155 was used to add an URI to the token. 
 Inherits ERC1155Burnable for burn functionality.
 */
contract Po is ERC1155Burnable, AccessControl {
    error CannotBeZeroAddress();
    error FunctionIsFrozen();
    error InvalidTokenId(uint256 id, uint256 participationTokenId);
    error NoPendingAdmin();
    error NotAContract(address);
    error NotPendingAdmin(address caller);
    error SameAddress();
    error Unauthorized(address user);

    address public admin;
    address public pendingAdmin;
    address public govOpsContract;
    string private constant _NAME = "Participation Token";
    string private constant _SYMBOL = "PO";
    bool internal _frozenUri = false;
    bool internal _frozenGovOps = false;
    string private _uri;
    uint256 private constant _PARTICIPATION_TOKEN_ID = 0;
    uint256 private _totalSupply;

    event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferAccepted(address indexed oldAdmin, address indexed newAdmin);
    event Frozen(address indexed user, bool indexed frozen);
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
     * @dev Returns the name of the token.
     */
    function name() external pure returns (string memory) {
        return _NAME;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external pure returns (string memory) {
        return _SYMBOL;
    }

    /**
     * @dev Returns the total supply of the token.
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Sets the governance operations contract address.
     * @param newGovOps Address of the new governance operations.
     */
    function setGovOps(
        address newGovOps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_frozenGovOps) revert FunctionIsFrozen();
        if (newGovOps == address(0)) revert CannotBeZeroAddress();
        if (govOpsContract != address(0)) {
            _revokeRole(MINTER_ROLE, govOpsContract);
        }
        uint256 size;
        assembly {
            size := extcodesize(newGovOps)
        }
        if (size == 0) revert NotAContract(newGovOps);

        govOpsContract = newGovOps;
        _grantRole(MINTER_ROLE, govOpsContract);
        emit GovOpsSet(msg.sender, newGovOps);
    }

    /**
     * @dev Overrides the renounceRole function to prevent renouncing the admin role.
     * @param role The role being renounced
     * @param account The account renouncing the role
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        if (role == DEFAULT_ADMIN_ROLE) {
            revert Unauthorized(msg.sender);
        }
        super.renounceRole(role, account);
    }

    /**
     * @dev Initiates the transfer of admin role to a new address.
     * The new admin must accept the role by calling acceptAdmin().
     * @param newAdmin The address to be set as the pending admin.
     */
    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert CannotBeZeroAddress();
        if (newAdmin == msg.sender) revert SameAddress();
        if (newAdmin == pendingAdmin) revert SameAddress();
        
        pendingAdmin = newAdmin;
        emit AdminTransferInitiated(msg.sender, newAdmin);
    }

    /**
     * @dev Accepts the admin role transfer. Can only be called by the pending admin.
     */
    function acceptAdmin() external {
        if (pendingAdmin == address(0)) revert NoPendingAdmin();
        if (msg.sender != pendingAdmin) revert NotPendingAdmin(msg.sender);

        address oldAdmin = admin;
        admin = pendingAdmin;
        pendingAdmin = address(0);

        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        emit AdminTransferAccepted(oldAdmin, admin);
    }

    /**
     * @dev Freezes the base URI, preventing any further changes.
     */
    function freezeUri() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozenUri = true;
        emit Frozen(msg.sender, _frozenUri);
    }

    /**
     * @dev Freezes the governance operations address, preventing any further changes.
     */
    function freezeGovOps() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozenGovOps = true;
        emit Frozen(msg.sender, _frozenGovOps);
    }

    /**
     * @dev Mints a specified amount of participation tokens to a user.
     * @param user Address of the user to mint tokens to.
     * @param amount the amount of tokens to be minted
     */
    function mint(address user, uint256 amount) external onlyRole(MINTER_ROLE) {
        uint256 oldSupply = _totalSupply;
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
        uint256 oldSupply = _totalSupply;

        for (uint256 i = 0; i < users.length; i++) {
            _totalSupply += amount;
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
        uint256 oldSupply = _totalSupply;
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
        if (_frozenUri) revert FunctionIsFrozen();
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
