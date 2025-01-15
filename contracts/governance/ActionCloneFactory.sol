// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IAction.sol";

contract ActionCloneFactory is AccessControl, ReentrancyGuard {
    using Clones for address;

    error CannotBeZeroAddress();

    mapping(address => bool) public isFactoryAction;
    mapping(uint256 => ActionConfig) public actionConfigs;
    uint256 public actionTypesCount = 1;
    address public admin;

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

    constructor(
        address transaction_,
        address election_,
        address impeachment_,
        address parameterChange_
    ) {
        _addActionConfig("transaction", transaction_);
        _addActionConfig("election", election_);
        _addActionConfig("impeachment", impeachment_);
        _addActionConfig("parameterChange", parameterChange_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Adds a new action type configuration.
     * @dev Only callable by an address with the `DEFAULT_ADMIN_ROLE`.
     * @param name A human-readable name for this action type.
     * @param implementation The address of the contract that will serve as the clone’s implementation.
     * Emits an {ActionConfigAdded} event.
     */
    function _addActionConfig(
        string memory name,
        address implementation
    ) internal {
        actionConfigs[actionTypesCount] = ActionConfig({
            name: name,
            enabled: true,
            implementation: implementation
        });
        emit ActionConfigAdded(actionTypesCount, name, implementation);
        actionTypesCount++;
    }
    /**
     * @notice Adds a new action type configuration.
     * @dev Only callable by an address with the `DEFAULT_ADMIN_ROLE`.
     * @param name A human-readable name for this action type.
     * @param implementation The address of the contract that will serve as the clone’s implementation.
     * Emits an {ActionConfigAdded} event.
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
     * Emits an {ActionConfigUpdated} event.
     */
    function toggleActionConfig(
        uint256 actionType,
        bool enabled
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        actionConfigs[actionType].enabled = enabled;
        emit ActionConfigUpdated(actionType, enabled);
    }

    /**
     * @notice Creates a new action clone based on a specified action type.
     * @param actionType The identifier of the action type to clone (index in the `actionConfigs` mapping).
     * @param params Initialization parameters passed to the action’s `initialize()` method.
     * @return clone The address of the newly created clone contract.
     * Requirements:
     * - The action type must be enabled.
     * - The cloned contract must implement an `initialize(bytes memory params)` function conforming to `IAction`.
     * Emits an {ActionCreated} event.
     */
    function createAction(
        uint256 actionType,
        bytes memory params
    ) external returns (address) {
        ActionConfig memory config = actionConfigs[actionType];
        require(config.enabled, "Action type not enabled");

        address clone = config.implementation.clone();
        IAction(clone).initialize(params);
        isFactoryAction[clone] = true;

        emit ActionCreated(clone, config.name);
        return clone;
    }

    /**
     * @dev Updates the admin address and transfers admin role.
     * @param newAdmin_ The address to be set as the new admin.
     */
    function setAdmin(address newAdmin_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin_ == address(0)) revert CannotBeZeroAddress();
        address oldAdmin = admin;
        admin = newAdmin_;
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin_);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        emit AdminSet(oldAdmin, newAdmin_);
    }
}
