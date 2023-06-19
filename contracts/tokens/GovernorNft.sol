// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Counters.sol";

contract GovernorNft is ERC721 {
    using Counters for Counters.Counter;

    Counters.Counter public tokenId;

    constructor() ERC721("GovernorNFT", "GovNFT") {
        
    }

    function mint(address receiver) external {
        tokenId.increment();
        uint256 _tokenId = tokenId.current();
        _safeMint(receiver, _tokenId);
    }
}