// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "./ActionCloneFactoryBase.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import "../interfaces/IAction.sol";

contract ActionCloneFactoryResearch is ActionCloneFactoryBase {
    using Clones for address;
    
    address public govResContract;
    address public immutable ADMIN = 0x96f67a852f8D3Bc05464C4F91F97aACE060e247A;
    
    event GovResSet(address indexed user, address indexed newAddress);
    
    constructor(address govRes_, address transaction_) {
        if (govRes_ == address(0) || transaction_ == address(0))
            revert CannotBeZeroAddress();

        govResContract = govRes_;
        _addActionConfig("transaction", transaction_); //1
        _grantRole(DEFAULT_ADMIN_ROLE, ADMIN);
    }

    /**
     * @dev Sets the governance research contract address.
     * @param newGovRes Address of the new governance research.
     */
    function setGovRes(
        address newGovRes
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newGovRes == address(0)) revert CannotBeZeroAddress();

        uint256 size;
        assembly {
            size := extcodesize(newGovRes)
        }
        if (size == 0) revert NotAContract(newGovRes);

        govResContract = newGovRes;
        emit GovResSet(msg.sender, newGovRes);
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
        if (!(msg.sender == govResContract)) revert Unauthorized(msg.sender);

        ActionConfig memory config = actionConfigs[actionType];
        if (!config.enabled) revert ConfigDisabled();

        address clone = config.implementation.clone();
        IAction(clone).initialize(params);
        _registerAction(clone);

        emit ActionCreated(clone, config.name);
        return clone;
    }
}
