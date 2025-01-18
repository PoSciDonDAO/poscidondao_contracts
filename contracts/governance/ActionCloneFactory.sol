// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IAction.sol";

contract ActionCloneFactory is AccessControl, ReentrancyGuard {
    using Clones for address;

    error CannotBeZeroAddress();
    error ConfigDisabled();
    error ZeroAddressImplementation();
    error EmptyActionName();
    error MaxActionTypesReached();
    error NotAContract(address implementation);
    error Unauthorized(address caller);

    mapping(address => bool) public isFactoryAction;
    mapping(uint256 => ActionConfig) public actionConfigs;
    uint256 public actionTypesCount = 1;
    address public admin;
    address public govOpsContract;
    address public govResContract;

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
        address parameterChange_,
        address govOps_,
        address govRes_
    ) {
        if (
            govOps_ == address(0) ||
            govRes_ == address(0) ||
            transaction_ == address(0) ||
            election_ == address(0) ||
            impeachment_ == address(0) ||
            parameterChange_ == address(0)
        ) revert CannotBeZeroAddress();

        govOpsContract = govOps_;
        govResContract = govRes_;
        _addActionConfig("transaction", transaction_); //1
        _addActionConfig("election", election_); //2
        _addActionConfig("impeachment", impeachment_); //3
        _addActionConfig("parameterChange", parameterChange_); //4
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new action config with the given name and implementation.
     *      Assigns an incremental ID, enables it by default, and emits ActionConfigAdded.
     * @param name The name identifier for this action type
     * @param implementation The contract to use as implementation for clones
     */
    function _addActionConfig(
        string memory name,
        address implementation
    ) internal {
        if (implementation == address(0)) revert ZeroAddressImplementation();
        if (bytes(name).length == 0) revert EmptyActionName();
        if (actionTypesCount >= type(uint256).max)
            revert MaxActionTypesReached();

        uint256 size;
        assembly {
            size := extcodesize(implementation)
        }
        if (size == 0) revert NotAContract(implementation);

        actionConfigs[actionTypesCount] = ActionConfig({
            name: name,
            enabled: true,
            implementation: implementation
        });
        emit ActionConfigAdded(actionTypesCount, name, implementation);
        actionTypesCount++;
    }
    /**
     * @dev Adds a new action type configuration.
     *      Only callable by an address with the `DEFAULT_ADMIN_ROLE`.
     * @param name A human-readable name for this action type.
     * @param implementation The address of the contract that will serve as the clone’s implementation.
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
     * @notice Creates a new action clone based on action type.
     * @param actionType The identifier of the action type to clone (index in the `actionConfigs` mapping).
     * @param params Initialization parameters passed to the action’s `initialize()` method.
     * @return clone The address of the newly created clone contract.
     */
    function createAction(
        uint256 actionType,
        bytes memory params
    ) external returns (address) {
        if (!(msg.sender == govOpsContract || msg.sender == govResContract))
            revert Unauthorized(msg.sender);
            
        ActionConfig memory config = actionConfigs[actionType];
        if (!config.enabled) revert ConfigDisabled();

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
