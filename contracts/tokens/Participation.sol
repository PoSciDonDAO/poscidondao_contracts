// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

contract Participation is AccessControl {

    error LengthMismatch();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error IncorrectAddress(address _chosenAddress);
    error Unauthorized(address user);

    address public treasuryWallet;
    address public govOps;
    address public staking;
    string public name = "Participation Token";
    string public symbol = "PO";
    bool internal frozen = false;
    string private _uri;
    uint256 public constant PARTICIPATION_TOKEN_ID = 0;
    uint256 public constant MINT_AMOUNT = 1;

    mapping(uint256 => mapping(address => uint256)) private _balances;

    modifier gov() {
        if (msg.sender != govOps) revert Unauthorized(msg.sender);
        _;
    }

    modifier stake() {
        if (msg.sender != staking) revert Unauthorized(msg.sender);
        _;
    }

    event Push(address indexed user, uint256 tokenId, uint256 amount);
    event Pull(address indexed user, uint256 tokenId, uint256 amount);
    event MintedTokenInfo(address receiver, uint256 tokenId, uint256 amount);
    event BurnedTokenInfo(address burner, uint256 tokenId, uint256 amount);
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    constructor(
        string memory baseURI_,
        address treasuryWallet_,
        address staking_
    ) {
        treasuryWallet = treasuryWallet_;
        staking = staking_;
        _setURI(baseURI_);
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the staking address
     */
    function setStaking(
        address _newStaking
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        staking = _newStaking;
    }

    /**
     * @dev sets the address of the governance smart contract
     */
    function setGovOps(address newGovOps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govOps = newGovOps;
    }

    /**
     * @dev freezes the current base URI
     */
    function freeze() external onlyRole(DEFAULT_ADMIN_ROLE) {
        frozen = true;
    }

    /**
     * @dev pushes participation tokens from user wallet to staking contract
     */
    function push(address user, uint256 amount) external stake {
        //transfer tokens from user to staking contract
        _safeTransferFrom(user, staking, PARTICIPATION_TOKEN_ID, amount, "");

        emit Push(user,  PARTICIPATION_TOKEN_ID, amount);
    }

    /**
     * @dev pulls participation tokens from staking contract to user wallet
     */
    function pull(address user, uint256 amount) external stake {
        //transfer tokens from staking contract to user
        _safeTransferFrom(staking, user, PARTICIPATION_TOKEN_ID, amount, "");

        //emit Pull event
        emit Pull(user, PARTICIPATION_TOKEN_ID, amount);
    }

    /**
     * @dev mints a PO token
     */
    function mint(address user) external gov {
        //mint token
        _mint(user, PARTICIPATION_TOKEN_ID, MINT_AMOUNT, "");

        //emit event
        emit MintedTokenInfo(user, PARTICIPATION_TOKEN_ID, MINT_AMOUNT);
    }

    /**
     * @dev burns a given amount of PO tokens for msg.sender
     */
    function burn(uint256 amount) external {
        //burn token
        _burn(msg.sender, PARTICIPATION_TOKEN_ID, amount);
        //emit event
        emit BurnedTokenInfo(msg.sender, PARTICIPATION_TOKEN_ID, amount);
    }

    /**
     * @dev sets the base URI
     * @param baseURI the ipfs base URI
     */
    function setURI(
        string memory baseURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!frozen);
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
        return _balances[PARTICIPATION_TOKEN_ID][account];
    }

    ///*** PUBLIC FUNCTION ***///

    /**
     *@dev   This function allows the generation of a URI for token Id 0 with the format {baseUri}/{id}/
     *       the id in this case is a decimal string representation of the token Id
     */
    function uri() public view returns (string memory) {
        return string(abi.encodePacked(_uri, "/", PARTICIPATION_TOKEN_ID));
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

    function _setURI(string memory newUri) internal {
        _uri = newUri;
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
        if (from == address(0)) revert IncorrectAddress(from);

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
