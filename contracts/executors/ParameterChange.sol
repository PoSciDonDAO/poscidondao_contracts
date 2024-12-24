// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorParams {
    function setGovernanceParameter(bytes32 param, uint256 data) external;
}

/**
 * @title ParameterChange
 * @dev Handles execution of changes to governance parameters.
 */
contract ParameterChange is ReentrancyGuard, AccessControl {
    error CannotBeZeroAddress();
    error InvalidParameter(bytes32 param);

    address public gov;
    address public governorExecutor;
    uint256 public data;
    bytes32 public param;
    string public humanReadableParam;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    event ActionExecuted(address indexed action, string indexed contractName);

    /**
     * @dev Constructor that initializes the ParameterChange contract.
     * @param govAddress_ The address of the Governor contract.
     * @param param_ The governance parameter (as a string) to be set.
     * @param data_ The value of the governance parameter.
     */
    constructor(
        address govAddress_,
        address governorExecutor_,
        string memory param_,
        uint256 data_
    ) {
        if (govAddress_ == address(0) || governorExecutor_ == address(0)) {
            revert CannotBeZeroAddress();
        }

        gov = govAddress_;
        governorExecutor = governorExecutor_;
        param = _toBytes32(param_);
        _checkValidParameter(param);
        humanReadableParam = param_;
        data = data_;
        _grantRole(GOVERNOR_ROLE, governorExecutor_);
    }

    /**
     * @dev Internal function to check if the parameter is valid.
     * @param param_ The parameter to check.
     */
    function _checkValidParameter(bytes32 param_) internal pure {
        if (
            param_ != _toBytes32("proposalLifetime") &&
            param_ != _toBytes32("quorum") &&
            param_ != _toBytes32("voteLockTime") &&
            param_ != _toBytes32("proposeLockTime") &&
            param_ != _toBytes32("voteChangeTime") &&
            param_ != _toBytes32("voteChangeCutOff") &&
            param_ != _toBytes32("maxVotingStreak") &&
            param_ != _toBytes32("opThreshold") &&
            param_ != _toBytes32("ddThreshold") &&
            param_ != _toBytes32("votingRightsThreshold")
        ) {
            revert InvalidParameter(param_);
        }
    }

    /**
     * @dev Convert a string to bytes32 format with padding.
     * @param source The string to convert.
     * @return result The bytes32 representation of the string.
     */
    function _toBytes32(
        string memory source
    ) internal pure returns (bytes32 result) {
        bytes memory tempBytes = bytes(source);
        if (tempBytes.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(tempBytes, 32))
        }
    }

    /**
     * @dev Execute the proposal to set a governance parameter.
     * @notice The GOVERNOR_ROLE is required to execute this function.
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        IGovernorParams(gov).setGovernanceParameter(param, data);
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
        emit ActionExecuted(address(this), "ParameterChange");
    }
}
