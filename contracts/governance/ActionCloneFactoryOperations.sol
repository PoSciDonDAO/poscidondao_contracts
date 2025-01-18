// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "./ActionCloneFactoryBase.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import "../interfaces/IAction.sol";

contract ActionCloneFactoryOperations is ActionCloneFactoryBase {
    using Clones for address;

    address public govOpsContract;

    constructor(
        address govOps_,
        address transaction_,
        address election_,
        address impeachment_,
        address parameterChange_
    ) {
        if (
            govOps_ == address(0) ||
            transaction_ == address(0) ||
            election_ == address(0) ||
            impeachment_ == address(0) ||
            parameterChange_ == address(0)
        ) revert CannotBeZeroAddress();

        govOpsContract = govOps_;
        _addActionConfig("transaction", transaction_); //1
        _addActionConfig("election", election_); //2
        _addActionConfig("impeachment", impeachment_); //3
        _addActionConfig("parameterChange", parameterChange_); //4
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
    ) external override returns (address) {
        if (msg.sender != govOpsContract) revert Unauthorized(msg.sender);

        ActionConfig memory config = actionConfigs[actionType];
        if (!config.enabled) revert ConfigDisabled();

        address clone = config.implementation.clone();
        IAction(clone).initialize(params);
        isFactoryAction[clone] = true;

        emit ActionCreated(clone, config.name);
        return clone;
    }
}
