// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Counters.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

// import "contracts/tokens/ImpactNft.sol";

contract Participation is AccessControl {
    using Counters for Counters.Counter;
    Counters.Counter public tokenIdCounter;

    error LengthMismatch();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error IncorrectAddress(address _chosenAddress);
    error NotGovernanceContract(address _govAddress);
    error Unauthorized(address user);

    address private _admin;
    address private _gov;
    string public name = "Participation Token";
    string public symbol = "PO";
    bool internal _frozen = false;
    string private _uri;
    address private _staking;

    mapping(uint256 => mapping(address => uint256)) private _balances;

    modifier onlyGov() {
        if (msg.sender != _gov) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyStake() {
        if (msg.sender != _staking) revert Unauthorized(msg.sender);
        _;
    }

    event Push(address indexed user, uint256 amount, uint256 tokenId);
    event Pull(address indexed user, uint256 amount, uint256 tokenId);
    event MintedTokenInfo(address receiver, uint256 tokenId, uint256 amount);
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    constructor(string memory baseURI_, address admin_, address staking_) {
        _admin = admin_;
        _staking = staking_;
        _setURI(baseURI_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the staking address
     */
    function setStaking(
        address _newStaking
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _staking = _newStaking;
    }

    /**
     * @dev sets the address of the governance smart contract
     */
    function setGov(address newGov) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _gov = newGov;
    }

    /**
     * @dev freezes the current base URI
     */
    function freeze() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozen = true;
    }

    /**
     * @dev pushes participation tokens from user wallet to staking contract
     */
    function push(address user, uint256 amount) external onlyStake {
        //transfer tokens from user to staking contract
        _safeTransferFrom(user, _staking, 0, amount, "");

        emit Push(user, amount, 1);
    }

    /**
     * @dev pulls participation tokens from staking contract to user wallet
     */
    function pull(address user, uint256 amount) external onlyStake {
        //transfer tokens from staking contract to user
        _safeTransferFrom(_staking, user, 0, amount, "");

        //emit Pull event
        emit Pull(user, amount, 1);
    }

    /**
     * @dev mints a PO NFT
     * @param user the address of the user that participated in governance
     */
    function mint(address user) external onlyGov {
        //mint token
        _mint(user, 0, 1, "");

        //emit event
        emit MintedTokenInfo(user, 0, 1);
    }

    /**
     * @dev returns the staking contract address
     */
    function getStaking() external view returns (address) {
        return _staking;
    }

    ///*** PUBLIC FUNCTIONS ***///

    /**
     * @dev sets the base URI
     * @param baseURI the ipfs base URI
     */
    function setURI(
        string memory baseURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!_frozen);
        _setURI(baseURI);
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account) external view returns (uint256) {
        if (account == address(0)) revert IncorrectAddress(account);
        return _balances[0][account];
    }

    /**
     *@dev   This function allows the generation of a URI for a specific token Id with the format {baseUri}/{id}/
     *       the id in this case is a decimal string representation of the token Id
     *@param tokenId is the token Id to generate or return the URI for.
     */
    function uri(uint256 tokenId) public view returns (string memory) {
        return string(abi.encodePacked(_uri, "/", Strings.toString(tokenId)));
    }

    ///*** INTERNAL FUNCTIONS ***///

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        if (to == address(0)) revert IncorrectAddress(to);

        address operator = msg.sender;
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        uint256 fromBalance = _balances[id][from];
        require(
            fromBalance >= amount,
            "ERC1155: insufficient balance for transfer"
        );
        unchecked {
            _balances[id][from] = fromBalance - amount;
        }
        _balances[id][to] += amount;

        emit TransferSingle(operator, from, to, id, amount);
    }

    function _setURI(string memory newuri) internal {
        _uri = newuri;
    }

    /**
     * @dev Creates `amount` tokens of token type `id`, and assigns them to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal {
        if (to == address(0)) revert IncorrectAddress(to);

        address operator = msg.sender;
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        _balances[id][to] += amount;
        emit TransferSingle(operator, address(0), to, id, amount);
    }

    /**
     * @dev Destroys `amount` tokens of token type `id` from `from`
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `from` must have at least `amount` tokens of token type `id`.
     */
    function _burn(address from, uint256 id, uint256 amount) internal virtual {
        require(from != address(0), "ERC1155: burn from the zero address");

        address operator = msg.sender;
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        uint256 fromBalance = _balances[id][from];
        require(fromBalance >= amount, "ERC1155: burn amount exceeds balance");
        unchecked {
            _balances[id][from] = fromBalance - amount;
        }

        emit TransferSingle(operator, from, address(0), id, amount);
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
    ) internal {}

    function _asSingletonArray(
        uint256 element
    ) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }
}
