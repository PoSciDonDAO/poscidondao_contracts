// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Counters.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
// import "contracts/tokens/ImpactNft.sol";

contract Participation {
    using Counters for Counters.Counter;

    error LengthMismatch();
    error InsufficientBalance();
    error IncorrectAddress(address _chosenAddress);
    error NotGovernanceContract(address _govAddress);
    error Unauthorized(address user);


    address public daoAddress;
    address public govRes;
    address public govOps;
    string public name = "Participation Token";
    string public symbol = "PO";
    bool internal _frozen = false;
    string private _uri;
    address private _stakingContract;

    Counters.Counter public tokenIdCounter;

    // NftLike public immutable govNft;
    // NftLike public impactNft;
    // Mapping from token ID to account balances
    mapping(uint256 => mapping(address => uint256)) private _balances;
    mapping(address => uint8) public wards;

    ///*** MODIFIER ***///
    modifier dao() {
        if(wards[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    modifier gov() {
        require(msg.sender == govRes || msg.sender == govOps, "Not a gov contract");
        _;
    }
    
    /*** EVENTS ***/
    event RelyOn(address indexed user);
    event Denied(address indexed user);
    event MintedTokenInfo(address receiver, uint256 tokenId);
    
    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    constructor(
        string memory baseURI_,
        address daoAddress_
        //address impactNft_
    ) {
        daoAddress = daoAddress_;
        // impactNft = NftLike(impactNft_);
        wards[daoAddress_] = 1;
        setURI(baseURI_);
    }

    /**
     * @dev sets the address of the governance smart contract
     */
    function setGovRes(address _newGovRes) external dao {
        govRes = _newGovRes;
    }

    /**
     * @dev sets the address of the governance smart contract
     */
    function setGovOps(address _newGovOps) external dao {
        govOps = _newGovOps;
    }

    /**
     * @dev freezes the current base URI
     */
    function freeze() external dao {
        _frozen = true;
    }


    /**
     * @dev sets the base URI
     * @param _baseURI the ipfs base URI
     */
    function setURI(string memory _baseURI) public dao {
        require(!_frozen);
        _setURI(_baseURI);
    }

    /**
     * @dev adds a gov
     * @param _user the user that is eligible to become a gov
     */
    function addWard(
        address _user
        ) external dao {
        wards[_user] = 1;
        emit RelyOn(_user);
    }

    /**
     * @dev removes a gov
     * @param _user the user that will be removed as a gov
     */
    function removeWard(
        address _user
        ) external dao {
        if(wards[_user] != 1) {
            revert Unauthorized(_user);
        }
        delete wards[_user];
        emit Denied(_user);
    }

    /**
    *@dev   This function allows the generation of a URI for a specific token Id with the format {baseUri}/{id}/
    *       the id in this case is a decimal string representation of the token Id
    *@param tokenId is the token Id to generate or return the URI for.     
    */
    function uri(uint256 tokenId) public view returns (string memory) {
        return string(abi.encodePacked(_uri, "/", Strings.toString(tokenId)));
    }


    // function setNftAddress(address _newImpactNft) public dao {
    //     impactNft = NftLike(_newImpactNft); 
    // }

    /**
     * @dev mints a PO NFT
     * @param _participant the address of the user that participated in governance
     */
    function mint(address _participant) external gov {
        tokenIdCounter.increment();
        uint256 tokenId = tokenIdCounter.current(); 
        _mint(_participant, tokenId, 1, "");
        emit MintedTokenInfo(_participant, tokenId);
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) public view virtual returns (uint256) {
        require(account != address(0), "ERC1155: address zero is not a valid owner");
        return _balances[id][account];
    }

    /**
     * @dev See {IERC1155-balanceOfBatch}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        virtual
        returns (uint256[] memory)
    {
        if(ids.length != accounts.length) revert LengthMismatch();

        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }

        return batchBalances;
    }

    /**
     * @dev pushes participation tokens from user wallet to staking contract
     */
    function push(
        address _user,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public virtual {
        if(_user != msg.sender) revert Unauthorized(_user);

        _safeBatchTransferFrom(_user, _stakingContract, ids, amounts, '');
    }

    /**
     * @dev pulls participation tokens from staking contract to user wallet
     */
    function pull(
        address _user,
        uint256[] memory _ids,
        uint256[] memory _amounts
    ) public virtual {
        if(_user != msg.sender) revert Unauthorized(_user);
        _safeBatchTransferFrom(_stakingContract, _user, _ids, _amounts, '');
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {
        if(ids.length != amounts.length) revert LengthMismatch();
        if(to == address(0)) revert IncorrectAddress(to);

        address operator = msg.sender;

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            uint256 fromBalance = _balances[id][from];
            if(fromBalance <= amount) revert InsufficientBalance();
            unchecked {
                _balances[id][from] = fromBalance - amount;
            }
            _balances[id][to] += amount;
        }

        emit TransferBatch(operator, from, to, ids, amounts);
    }


    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }


    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        if (to == address(0)) revert IncorrectAddress(to);
        
        address operator = msg.sender;
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        _balances[id][to] += amount;
        emit TransferSingle(operator, address(0), to, id, amount);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_burn}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     */
    function _burnBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual {
        if (from == address(0)) revert IncorrectAddress(from);
        if(ids.length != amounts.length) revert LengthMismatch();

        address operator = msg.sender;

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            uint256 fromBalance = _balances[id][from];
            if(fromBalance <= amount) revert InsufficientBalance();
            unchecked {
                _balances[id][from] = fromBalance - amount;
            }
        }

        emit TransferBatch(operator, from, address(0), ids, amounts);
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning, as well as batched variants.
     *
     * The same hook is called on both single and batched variants. For single
     * transfers, the length of the `ids` and `amounts` arrays will be 1.
     *
     * Calling conditions (for each `id` and `amount` pair):
     *
     * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * of token type `id` will be  transferred to `to`.
     * - When `from` is zero, `amount` tokens of token type `id` will be minted
     * for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens of token type `id`
     * will be burned.
     * - `from` and `to` are never both zero.
     * - `ids` and `amounts` have the same, non-zero length.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {}


    function _asSingletonArray(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

}
