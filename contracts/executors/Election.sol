// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorRoleGrant {
    function grantDueDiligenceRole(address[] memory members) external;
    function checkDueDiligenceRole(address member) external returns (bool);
}

/**
 * @title Election
 * @dev Facilitates the election of scientists that govern the research funding process.
 */
contract Election is ReentrancyGuard, AccessControl {
    error AddressAlreadyHasDDRole();
    error AlreadyInitialized();
    error CannotBeZeroAddress();
    error FactoryAlreadySet();
    error FactoryNotSet();
    error NotAContract(address);
    error Unauthorized(address caller);

    address[] internal _targetWallets;
    address public governorResearch;
    address public governorExecutor;
    address public factory;
    bool private _initialized;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    address public constant ADMIN = 0x96f67a852f8D3Bc05464C4F91F97aACE060e247A;

    event ActionExecuted(address indexed action, string indexed contractName);
    event FactorySet(address indexed user, address newAddress);
    event Initialized(
        address[] targetWallets,
        address governorResearch,
        address governorExecutor
    );
    /**
     * @dev Constructor that grants DEFAULT_ADMIN_ROLE to ADMIN address
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, ADMIN);
    }

    /**
     * @dev Sets the new factory contract address for Election
     * @param newFactory The address to be set as the factory contract
     */
    function setFactory(
        address newFactory
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFactory == address(0)) revert CannotBeZeroAddress();
        if (factory != address(0)) revert FactoryAlreadySet();
        uint256 size;
        assembly {
            size := extcodesize(newFactory)
        }
        if (size == 0) revert NotAContract(newFactory);

        factory = newFactory;
        emit FactorySet(msg.sender, newFactory);
    }

    /**
     * @dev Initializes the election contract
     * @param params Encoded parameters (targetWallets, governorResearch, governorExecutor)
     */
    function initialize(bytes memory params) external {
        if (msg.sender != factory) revert Unauthorized(msg.sender);
        if (factory == address(0)) revert FactoryNotSet();
        if (_initialized) revert AlreadyInitialized();
        (
            address[] memory targetWallets_,
            address governorResearch_,
            address governorExecutor_
        ) = abi.decode(params, (address[], address, address));

        if (
            governorResearch_ == address(0) || governorExecutor_ == address(0)
        ) {
            revert CannotBeZeroAddress();
        }

        for (uint256 i = 0; i < targetWallets_.length; i++) {
            if (targetWallets_[i] == address(0)) {
                revert CannotBeZeroAddress();
            }
            if (
                IGovernorRoleGrant(governorResearch_).checkDueDiligenceRole(
                    targetWallets_[i]
                )
            ) {
                revert AddressAlreadyHasDDRole();
            }
        }

        _targetWallets = targetWallets_;
        governorResearch = governorResearch_;
        governorExecutor = governorExecutor_;
        _grantRole(GOVERNOR_ROLE, governorExecutor_);

        _initialized = true;
        emit Initialized(targetWallets_, governorResearch_, governorExecutor_);
    }

    /**
     * @dev Returns all elected wallets
     */
    function getAllElectedWallets() public view returns (address[] memory) {
        return _targetWallets;
    }

    /**
     * @dev Execute the proposal to elect a scientist
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        IGovernorRoleGrant(governorResearch).grantDueDiligenceRole(
            _targetWallets
        );
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
        emit ActionExecuted(address(this), "Election");
    }
}
