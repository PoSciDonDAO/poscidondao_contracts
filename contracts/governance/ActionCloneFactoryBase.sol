// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

abstract contract ActionCloneFactoryBase is AccessControl, ReentrancyGuard {
    error ActionTypeNotFound(uint256 actionType);
    error ActionTypeAlreadyExists(string name);
    error CannotBeZeroAddress();
    error ConfigDisabled();
    error EmptyActionName();
    error NotAContract(address implementation);
    error SameAddress();
    error Unauthorized(address caller);
    error ZeroAddressImplementation();

    mapping(address => bool) public isFactoryAction;
    mapping(uint256 => ActionConfig) public actionConfigs;
    mapping(string => bool) private _actionNameExists;
    uint256 public actionTypesCount = 1;
    address public admin = 0x96f67a852f8D3Bc05464C4F91F97aACE060e247A;

    struct ActionConfig {
        string name;
        bool enabled;
        address implementation;
    }

    event ActionCreated(address indexed action, string actionType);
    event ActionConfigAdded(
        uint256 indexed actionType,
        string name,
        address implementation
    );
    event ActionConfigUpdated(uint256 indexed actionType, bool enabled);
    event AdminSet(address indexed user, address indexed newAddress);


    /**
     * @dev Creates a new action config with the given name and implementation.
     *      Assigns an incremental ID and enables it by default.
     * @param name The name identifier for this action type
     * @param implementation The contract to use as implementation for clones
     */
    function _addActionConfig(
        string memory name,
        address implementation
    ) internal {
        if (implementation == address(0)) revert ZeroAddressImplementation();
        if (bytes(name).length == 0) revert EmptyActionName();
        if (_actionNameExists[name]) revert ActionTypeAlreadyExists(name);

        uint256 size;
        assembly {
            size := extcodesize(implementation)
        }
        if (size == 0) revert NotAContract(implementation);

        _actionNameExists[name] = true;
        actionConfigs[actionTypesCount] = ActionConfig({
            name: name,
            enabled: true,
            implementation: implementation
        });
        actionTypesCount++;
        emit ActionConfigAdded(actionTypesCount, name, implementation);
    }

    /**
     * @dev Adds a new action type configuration.
     *      Only callable by an address with the `DEFAULT_ADMIN_ROLE`.
     * @param name A human-readable name for this action type.
     * @param implementation The address of the contract that will serve as the clone's implementation.
     */
    function addActionConfig(
        string memory name,
        address implementation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addActionConfig(name, implementation);
    }

    /**
     * @notice Enables or disables an existing action type.
     * @dev Only callable by an address with the `DEFAULT_ADMIN_ROLE`.
     * @param actionType The identifier of the action type (index in the `actionConfigs` mapping).
     * @param enabled A boolean indicating whether this action type should be marked as enabled or disabled.
     */
    function toggleActionConfig(
        uint256 actionType,
        bool enabled
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bytes(actionConfigs[actionType].name).length == 0) {
            revert ActionTypeNotFound(actionType);
        }
        actionConfigs[actionType].enabled = enabled;
        emit ActionConfigUpdated(actionType, enabled);
    }

    /**
     * @dev Updates the admin address and transfers admin role.
     * @param newAdmin_ The address to be set as the new admin.
     */
    function setAdmin(address newAdmin_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin_ == address(0)) revert CannotBeZeroAddress();
        if (newAdmin_ == msg.sender) revert SameAddress();
        address oldAdmin = admin;
        admin = newAdmin_;
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin_);
        emit AdminSet(oldAdmin, newAdmin_);
    }

    /**
     * @notice Creates a new action clone based on action type.
     * @param actionType The identifier of the action type to clone (index in the `actionConfigs` mapping).
     * @param params Initialization parameters passed to the action's `initialize()` method.
     * @return clone The address of the newly created clone contract.
     */
    function createAction(
        uint256 actionType,
        bytes memory params
    ) external virtual returns (address);
}
