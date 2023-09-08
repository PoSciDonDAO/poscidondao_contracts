// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Counters.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
// import "contracts/tokens/ImpactNft.sol";

contract Participation {
    using Counters for Counters.Counter;
    Counters.Counter public tokenIdCounter;

    error LengthMismatch();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
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
   
    mapping(uint256 => mapping(address => uint256)) private _balances;
    mapping(address => Ids) private _tokenBalances;
    mapping(address _stakingContract => mapping(address => Ids)) private _stakedBalance;
    mapping(address => uint8) public wards;

    modifier dao() {
        if(wards[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    modifier gov() {
        if(msg.sender != govRes && msg.sender != govOps) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyStake() {
        if(msg.sender != _stakingContract) revert Unauthorized(msg.sender);
        _;
    }
    
    struct Ids {
        uint256[] ids;
    }

    event RelyOn(address indexed user);
    event Denied(address indexed user);
    event Push(address indexed user, uint256 amount);
    event Pull(address indexed user, uint256 amount);
    event MintedTokenInfo(address receiver, uint256 tokenId);
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    constructor(
        string memory baseURI_,
        address daoAddress_
    ) {
        daoAddress = daoAddress_;
        wards[daoAddress_] = 1;
        setURI(baseURI_);
    }

    /**
     * @dev sets the staking address
     */
    function setStakingContract(address _newStakingContract) external dao {
        _stakingContract = _newStakingContract;
    }

    /**
     * @dev returns the staking contract
     */
    function stakingContract() external view returns (address) {
        return _stakingContract;
    }

    /**
     * @dev sets the address of the governance smart contract
     */
    function setGovRes(address newGovRes) external dao {
        govRes = newGovRes;
    }

    /**
     * @dev sets the address of the governance smart contract
     */
    function setGovOps(address newGovOps) external dao {
        govOps = newGovOps;
    }

    /**
     * @dev freezes the current base URI
     */
    function freeze() external dao {
        _frozen = true;
    }

    /**
     * @dev adds a gov
     * @param user the user that is eligible to become a gov
     */
    function addWard(address user) external dao {
        wards[user] = 1;
        emit RelyOn(user);
    }

    /**
     * @dev removes a gov
     * @param user the user that will be removed as a gov
     */
    function removeWard(address user) external dao {
        if(wards[user] != 1) {
            revert Unauthorized(user);
        }
        delete wards[user];
        emit Denied(user);
    }

    /**
     * @dev pushes participation tokens from user wallet to staking contract
     */
    function push(
        address user,
        uint256 amount
    ) external onlyStake {
        uint256[] memory balance = getHeldBalance(user);
        uint256[] memory ids = _turnTokenIdsIntoArray(balance, amount);
        _safeBatchTransferFrom(
            user, 
            _stakingContract, 
            ids, 
            _turnAmountIntoArray(amount),
            '');
        
        for(uint256 i = 0; i < ids.length; i++) {
            _stakedBalance[_stakingContract][user].ids.push(ids[i]);
        }
    }

    /**
     * @dev pulls participation tokens from staking contract to user wallet
     */
    function pull(
        address user,
        uint256 amount
    ) external onlyStake {
        uint256[] memory balance = getStakedBalance(user);
        uint256[] memory ids = _turnTokenIdsIntoArray(balance, amount);
        _safeBatchTransferFrom(
            _stakingContract,
            user, 
            ids, 
            _turnAmountIntoArray(amount),
            '');
            
            for(uint256 i = 0; i < ids.length; i++) {
            _stakedBalance[_stakingContract][user].ids.pop();
        }
    }


    /**
     * @dev mints a PO NFT
     * @param user the address of the user that participated in governance
     */
    function mint(address user) external gov {
        tokenIdCounter.increment();
        uint256 tokenId = tokenIdCounter.current(); 
        _mint(user, tokenId, 1, "");
        _tokenBalances[user].ids.push(tokenId);
        emit MintedTokenInfo(user, tokenId);
    }

    /**
    *@dev   This function allows the generation of a URI for a specific token Id with the format {baseUri}/{id}/
    *       the id in this case is a decimal string representation of the token Id
    *@param tokenId is the token Id to generate or return the URI for.     
    */
    function uri(uint256 tokenId) public view returns (string memory) {
        return string(abi.encodePacked(_uri, "/", Strings.toString(tokenId)));
    }
    
    /**
     * @dev sets the base URI
     * @param baseURI the ipfs base URI
     */
    function setURI(string memory baseURI) public dao {
        require(!_frozen);
        _setURI(baseURI);
    }

    /**
     * @dev returns an array of token ids held by the user
     * @param user the user address of interest
     */
    function getHeldBalance(address user) public view returns (uint256[] memory) {
        return _tokenBalances[user].ids;
    }

    /**
     * @dev returns an array of token ids held by the staking smart contract
     * @param user the user address of interest
     */
    function getStakedBalance(address user) public view returns (uint256[] memory) {
        return _stakedBalance[_stakingContract][user].ids;
    }


    /**
    *@dev Using this function, a given amount will be turned into an array.
    *     This array will be used in ERC1155's batch mint function. 
    *@param amount is the amount provided that will be turned into an array.
    */
    function _turnAmountIntoArray(uint256 amount) internal pure returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint[](amount);
        for (uint256 i = 0; i < amount;) {
            tokenAmounts[i] = i + 1;
            unchecked {
                i++;
            }
        }
    }

    /**
    * @dev A given amount will be turned into an array.
    *      This array will be used in ERC1155's batch mint function.
    * @param balance is an array containing the token ids of the user
    * @param amount is the amount provided that will be turned into an array.
    */
    function _turnTokenIdsIntoArray(uint256[] memory balance, uint256 amount) internal pure returns (uint256[] memory tokenIdArray) {
        tokenIdArray = new uint[](_turnAmountIntoArray(amount).length);
        for (uint256 i = 0; i < _turnAmountIntoArray(amount).length;) { 
            uint256 tokenId = balance[i];
            tokenIdArray[i] = tokenId;
            unchecked {
                i++;
            }  
        }
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
            if(fromBalance < amount) revert InsufficientBalance(fromBalance, amount);
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
            if(fromBalance < amount) revert InsufficientBalance(fromBalance, amount);
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
