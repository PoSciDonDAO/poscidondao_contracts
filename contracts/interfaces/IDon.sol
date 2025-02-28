// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

/**
 * @title IDon
 * @dev Interface for the Donation Token (DON) contract
 */
interface IDon {
    /**
     * @dev Mints a new donation token to a user with a specific amount and metadata.
     * @param user Address of the user to mint token to.
     * @param amount The donation amount to associate with this token.
     * @param metadata Optional metadata string to associate with this token.
     * @return tokenId The ID of the newly minted token.
     */
    function mint(address user, uint256 amount, string memory metadata) external returns (uint256);
    
    /**
     * @dev Returns the total number of tokens in existence.
     */
    function totalSupply() external view returns (uint256);
    
    /**
     * @dev Returns the donation amount associated with a token.
     * @param tokenId ID of the token to query.
     */
    function getDonationAmount(uint256 tokenId) external view returns (uint256);
}