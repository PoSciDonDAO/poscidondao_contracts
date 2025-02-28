// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Counters.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

/**
 * @title Donation Token (DON)
 * @dev A soulbound ERC721 token for donations. These tokens are mintable but not transferable,
 * adhering to the soulbound token concept where tokens are permanently associated with a wallet.
 * Implements EIP-5192 for soulbound token interface.
 * 
 * Security considerations:
 * - Tokens cannot be transferred between addresses (soulbound)
 * - Only the donation contract can mint tokens
 * - Admin can batch mint tokens for special cases
 * - URI and donation address can be frozen to prevent changes
 */
contract Don is ERC721Enumerable, ERC721URIStorage, AccessControl {
    using Counters for Counters.Counter;
    using Strings for uint256;

    // Errors
    error Frozen();
    error Unauthorized(address user);
    error SoulboundTokenCannotBeTransferred();
    error ZeroAddress();
    error TokenDoesNotExist(uint256 tokenId);
    error ArrayLengthMismatch();

    // Events
    event DonationAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event BaseURIUpdated(string newBaseURI);
    event DonationMinted(address indexed to, uint256 indexed tokenId, uint256 amount, string metadata);
    event DonationBurned(address indexed from, uint256 indexed tokenId);
    event URIFrozen();
    event DonationAddressFrozen();
    event DonationAddressUnfrozen();
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    // State variables
    address public admin;
    address public donationAddress;
    string public baseURI;
    bool internal _frozenUri = false;
    bool internal _frozenDonation = false;
    Counters.Counter private _tokenIdCounter;
    
    // Mapping to store donation amounts for each token
    mapping(uint256 => uint256) private _donationAmounts;
    
    // EIP-5192: Minimal Soulbound NFT interface
    bytes4 private constant _INTERFACE_ID_ERC5192 = 0xb45a3c0e;

    /**
     * @dev Modifier to restrict actions to the Donation address.
     */
    modifier onlyDonation() {
        if (msg.sender != donationAddress) revert Unauthorized(msg.sender);
        _;
    }

    /**
     * @dev Constructor initializes the contract with a base URI and admin address.
     * @param baseURI_ The base URI for token metadata.
     * @param treasuryWallet_ The address that will have admin privileges.
     */
    constructor(
        string memory baseURI_,
        address treasuryWallet_
    ) ERC721("Donation Token", "DON") {
        if (treasuryWallet_ == address(0)) revert ZeroAddress();
        
        admin = treasuryWallet_;
        baseURI = baseURI_;
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
    }

    /**
     * @dev Sets the donation address that can mint tokens.
     * @param newDonationAddress Address of the new donation contract.
     */
    function setDonation(
        address newDonationAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_frozenDonation) revert Frozen();
        if (newDonationAddress == address(0)) revert ZeroAddress();
        
        address oldAddress = donationAddress;
        donationAddress = newDonationAddress;
        emit DonationAddressUpdated(oldAddress, newDonationAddress);
    }

    /**
     * @dev Unfreezes the donation address setting, allowing it to be changed.
     * Can only be called by the admin.
     */
    function unfreezeDonation() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozenDonation = false;
        emit DonationAddressUnfrozen();
    }

    /**
     * @dev Updates the admin address.
     * @param newAdmin The new admin address.
     */
    function setAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert ZeroAddress();
        
        address oldAdmin = admin;
        admin = newAdmin;
        
        // Update role
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        
        emit AdminUpdated(oldAdmin, newAdmin);
    }

    /**
     * @dev Returns the total number of tokens in existence.
     */
    function totalSupply() public view virtual override(ERC721Enumerable) returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @dev Freezes the base URI, preventing any further changes.
     */
    function freezeUri() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozenUri = true;
        emit URIFrozen();
    }

    /**
     * @dev Freezes the donation address, preventing any further changes.
     */
    function freezeDonation() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozenDonation = true;
        emit DonationAddressFrozen();
    }

    /**
     * @dev Mints a new donation token to a user with a specific amount.
     * @param user Address of the user to mint token to.
     * @param amount The donation amount to associate with this token.
     * @param metadata Optional metadata string to associate with this token.
     * @return tokenId The ID of the newly minted token.
     */
    function mint(
        address user, 
        uint256 amount, 
        string memory metadata
    ) external onlyDonation returns (uint256) {
        if (user == address(0)) revert ZeroAddress();
        
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        
        _safeMint(user, tokenId);
        
        // Store donation amount
        _donationAmounts[tokenId] = amount;
        
        // Set token URI if metadata is provided
        if (bytes(metadata).length > 0) {
            _setTokenURI(tokenId, metadata);
        }
        
        emit DonationMinted(user, tokenId, amount, metadata);
        return tokenId;
    }

    /**
     * @dev Mints donation tokens to multiple users by the admin.
     * @param users Array of user addresses to mint tokens to.
     * @param amounts Array of donation amounts for each user.
     * @param metadata Optional metadata string to associate with these tokens.
     * @return Array of minted token IDs.
     */
    function mintBatchByAdmin(
        address[] memory users, 
        uint256[] memory amounts,
        string memory metadata
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256[] memory) {
        if (users.length != amounts.length) revert ArrayLengthMismatch();
        
        uint256[] memory tokenIds = new uint256[](users.length);
        
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == address(0)) revert ZeroAddress();
            
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            
            _safeMint(users[i], tokenId);
            
            // Store donation amount
            _donationAmounts[tokenId] = amounts[i];
            
            // Set token URI if metadata is provided
            if (bytes(metadata).length > 0) {
                _setTokenURI(tokenId, metadata);
            }
            
            tokenIds[i] = tokenId;
            emit DonationMinted(users[i], tokenId, amounts[i], metadata);
        }
        
        return tokenIds;
    }

    /**
     * @dev Burns a token. Can only be called by the token owner or an approved address.
     * @param tokenId ID of the token to burn.
     */
    function burn(uint256 tokenId) external {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized(_msgSender());
        
        address owner = ownerOf(tokenId);
        _burn(tokenId);
        emit DonationBurned(owner, tokenId);
    }

    /**
     * @dev Sets the base URI for all token IDs. Can only be called by admin
     * and if the URI has not been frozen.
     * @param newBaseURI New base URI to set.
     */
    function setBaseURI(string memory newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_frozenUri) revert Frozen();
        baseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @dev Returns the donation amount associated with a token.
     * @param tokenId ID of the token to query.
     * @return The donation amount.
     */
    function getDonationAmount(uint256 tokenId) external view returns (uint256) {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        return _donationAmounts[tokenId];
    }

    /**
     * @dev Returns all token IDs owned by an address.
     * @param owner Address to query.
     * @return Array of token IDs.
     */
    function getTokensOfOwner(address owner) external view returns (uint256[] memory) {
        if (owner == address(0)) revert ZeroAddress();
        
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](tokenCount);
        
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        
        return tokenIds;
    }

    /**
     * @dev Checks if a token is locked (soulbound). All tokens in this contract are soulbound.
     * @param tokenId The ID of the token to check.
     * @return Always returns true as all tokens are soulbound.
     */
    function locked(uint256 tokenId) external view returns (bool) {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        return true;
    }

    /**
     * @dev Base URI for computing {tokenURI}.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Override to prevent token transfers (soulbound implementation).
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId, 
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        // Allow minting (from == address(0)) and burning (to == address(0))
        // But prevent transfers between addresses
        if (from != address(0) && to != address(0)) {
            // Only allow admin to transfer tokens
            if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
                revert SoulboundTokenCannotBeTransferred();
            }
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, AccessControl) returns (bool) {
        return 
            interfaceId == _INTERFACE_ID_ERC5192 || // EIP-5192 (Soulbound)
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Required override for ERC721URIStorage and ERC721Enumerable compatibility.
     */
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Required override for ERC721URIStorage and ERC721Enumerable compatibility.
     */
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
        delete _donationAmounts[tokenId];
    }
}
