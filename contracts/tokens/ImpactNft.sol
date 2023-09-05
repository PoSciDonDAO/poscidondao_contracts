// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Counters.sol";
//import PO token interface

contract ImpactNft is ERC721 {
    using Counters for Counters.Counter;

    error Unauthorized(address user);
    error InsufficientPOBalance();
    error InsufficientPOTokensToConvert();

    uint256 public rateAverageImpact = 10;
    uint256 public rateHighImpact    = 20;
    uint256 public rateNatureImpact  = 50;
    uint256 public rateNobelImpact   = 100;

    Counters.Counter public tokenId;

    mapping(address => uint8) public wards;

    ///*** MODIFIER ***///
    modifier dao() {
        if(wards[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }


    constructor() ERC721("Impact NFT", "IMPACT") {
        
    }

    function setConversionRate(
        uint256 _rateAverageImpact, 
        uint256 _rateHighImpact, 
        uint256 _rateNatureImpact,
        uint256 _rateNobelImpact
         ) external dao {
        rateAverageImpact = _rateAverageImpact;
        rateHighImpact = _rateHighImpact;
        rateNatureImpact = _rateNatureImpact;
        rateNobelImpact = _rateNobelImpact;
    }

    // function convertPOToAverageImpactNft(uint256 amount, uint256 tokenId) external {
    //     // if (amount > balanceOf(msg.sender, tokenId)) revert InsufficientPOBalance();
    //     // if (balanceOf(msg.sender, tokenId) < rateAverageImpact) revert InsufficientPOTokensToConvert();

    //     // _burnBatch(msg.sender, 1, rateAverageImpact);
    //     //impactNft.mint(msg.sender);
    // }
    // function convertPOToHighImpactNft(uint256 amount, uint256 tokenId) external {
    //     // if (amount > balanceOf(msg.sender, tokenId)) revert InsufficientPOBalance();
    //     // if (balanceOf(msg.sender, tokenId) < rateHighImpact) revert InsufficientPOTokensToConvert();

    //     // _burnBatch(msg.sender, 1, rateHighImpact);
    //     //impactNft.mint(msg.sender);
    // }
    // function convertPOToNatureImpactNft(uint256 amount, uint256 tokenId) external {
    //     // if (amount > balanceOf(msg.sender, tokenId)) revert InsufficientPOBalance();
    //     // if (balanceOf(msg.sender, tokenId) < rateNatureImpact) revert InsufficientPOTokensToConvert();

    //     // _burnBatch(msg.sender, 1, rateNatureImpact);
    //     //impactNft.mint(msg.sender);
    // }
    // function convertPOToNobelImpactNft(uint256 amount, uint256 tokenId) external {
    //     // if (balanceOf(msg.sender, tokenId) < amount) revert InsufficientPOBalance();
    //     // if (balanceOf(msg.sender, tokenId) < rateNobelImpact) revert InsufficientPOTokensToConvert();

    //     // _burnBatch(msg.sender, tokenId, rateNobelImpact);
    //     //impactNft.mint(msg.sender);
    // }

    function mint(address receiver) external {
        tokenId.increment();
        uint256 _tokenId = tokenId.current();
        _safeMint(receiver, _tokenId);
    }
}