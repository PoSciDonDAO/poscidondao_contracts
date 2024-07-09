// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

/**
 * @title Participation
 * @dev A soulbound token contract for participation tokens. These tokens are mintable, burnable,
 * but not transferable, adhering to the soulbound token concept where tokens are permanently associated
 * with a wallet. Inherits ERC1155 for multi-token standard support and ERC1155Burnable for burn functionality.
 */
contract Po is ERC1155Burnable, AccessControl {
    error Frozen();
    error Unauthorized(address user);

    // State variables
    address public treasuryWallet; /// @notice Wallet address for treasury operations.
    address public govOpsAddress; /// @notice Governance operations address for administrative actions.
    string public name = "Participation Token"; /// @notice Human-readable name of the token.
    string public symbol = "PO"; /// @notice Abbreviated symbol of the token.
    bool internal frozenUri = false; /// @notice Indicates if the URI has been frozen.
    bool internal frozenGovOps = false; /// @notice Indicates if the GovOps contract address has been frozen.
    string private _uri; /// @notice Base URI for token metadata.
    uint256 private constant PARTICIPATION_TOKEN_ID = 0; /// @notice ID for Participation (PO) token.
    uint256 private constant MINT_AMOUNT = 1; /// @notice Standard mint amount.
    uint256 private _totalSupply;

    /**
     * @dev Modifier to restrict actions to the Governance Operations address.
     */
    modifier onlyGov() {
        if (msg.sender != govOpsAddress) revert Unauthorized(msg.sender);
        _;
    }

    /**
     * @dev Constructor for setting the base URI and treasury wallet address upon deployment.
     * @param baseURI_ Base URI for constructing token-specific URIs.
     * @param treasuryWallet_ Address of the treasury wallet.
     */
    constructor(
        string memory baseURI_,
        address treasuryWallet_
    ) ERC1155(baseURI_) {
        treasuryWallet = treasuryWallet_;
        _setURI(baseURI_);
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
    }

    /**
     * @dev Sets the governance operations address.
     * @param newGovOpsAddress Address of the new governance operations.
     */
    function setGovOps(
        address newGovOpsAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (frozenGovOps) revert Frozen();
        govOpsAddress = newGovOpsAddress;
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
     * @dev Freezes the base URI, preventing any further changes.
     */
    function freezeGovOps() external onlyRole(DEFAULT_ADMIN_ROLE) {
        frozenGovOps = true;
    }

    /**
     * @dev Mints a specified amount of participation tokens to a user.
     * @param user Address of the user to mint tokens to.
     */
    function mint(address user) external onlyGov {
        _mint(user, PARTICIPATION_TOKEN_ID, MINT_AMOUNT, "");
        _totalSupply += MINT_AMOUNT;
    }

    /**
     * @dev Mints a specified amount of participation tokens to a user.
     * @param account Address of the user to mint tokens to.
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
     * @dev Prevents token transfer functionality by always reverting the transaction.
     */
    function safeTransferFrom(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure override {
        revert("ERC1155Soulbound: token transfer disabled");
    }

    /**
     * @dev Prevents batch token transfer functionality by always reverting the transaction.
     */
    function safeBatchTransferFrom(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure override {
        revert("ERC1155Soulbound: token transfer disabled");
    }

    /**
     * @dev Generates a URI for a given token ID.
     * @return String representing the token URI.
     */
    function uri() public view returns (string memory) {
        return string(abi.encodePacked(_uri, "/", PARTICIPATION_TOKEN_ID));
    }
}
