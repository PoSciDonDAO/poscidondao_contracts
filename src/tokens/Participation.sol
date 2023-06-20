// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

interface NftLike {
    function mint(address, uint256) external;
}

contract Participation is ERC1155 {

    error Unauthorized(address user);
    error InsufficientBalance();

    uint256 private _rate;

    // NftLike public immutable govNft;
    NftLike public govNft;

    mapping(address => uint8) public govs;

    modifier gov() {
        if(govs[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    constructor(
        string memory _uri,
        address _govNft
    ) ERC1155(_uri) {
        // govNft = NftLike(_govNft);
    }

    function setNftAddress(address _newGovNft) public gov {
        govNft = NftLike(_newGovNft); 
    }

    function setConvertionRate(uint256) external gov {
        _rate = 10; 
    }

    function getCovertionRate() external view returns(uint256) {
        return _rate;
    }

    function convertToNFT(uint256 amount) external {
        if (amount > balanceOf(msg.sender, 1) 
        || balanceOf(msg.sender, 1) < _rate) revert InsufficientBalance();

        _burn(msg.sender, 1, _rate);
        govNft.mint(msg.sender, 1);
    }

    function mint(address participant) public {
        _mint(participant, 1, 1, "");
    }

}
