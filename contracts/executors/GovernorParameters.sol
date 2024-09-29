// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorParams {
    function setGovParams(bytes32 param, uint256 data) external;

    function checkExecutorRole(address member) external view returns (bool);
}

contract GovernorParameters is ReentrancyGuard, AccessControl {
    error IsNotExecutor(address contractAddress);
    error InvalidParameter(bytes32 param);

    IGovernorParams gov;

    bytes32 param;
    uint256 data;

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /**
     * @dev Constructor that initializes the GovernorParameters contract.
     * @param govAddress_ The address of the Governor contract.
     * @param param_ The governance parameter (as a string) to be set.
     * @param data_ The value of the governance parameter.
     */
    constructor(
        address govAddress_,
        address govExecAddress_,
        string memory param_,
        uint256 data_
    ) {
        gov = IGovernorParams(govAddress_);
        param = _toBytes32(param_); // Use the correct bytes32 format
        data = data_;
        _grantRole(EXECUTOR_ROLE, govExecAddress_);
        
        // Check if the provided param is valid
        _checkValidParameter(param);
    }

    /**
     * @dev Internal function to check if the parameter is valid.
     * @param param_ The parameter to check.
     */
    function _checkValidParameter(bytes32 param_) internal pure {
        if (
            param_ != _toBytes32("proposalLifeTime") &&
            param_ != _toBytes32("quorum") &&
            param_ != _toBytes32("voteLockTime") &&
            param_ != _toBytes32("proposeLockTime") &&
            param_ != _toBytes32("voteChangeTime") &&
            param_ != _toBytes32("voteChangeCutOff") &&
            param_ != _toBytes32("maxVotingStreak") &&
            param_ != _toBytes32("opThreshold") &&
            param_ != _toBytes32("ddThreshold")
        ) {
            revert InvalidParameter(param_);
        }
    }

    /**
     * @dev Convert a string to bytes32 format with padding.
     * @param source The string to convert.
     * @return result The bytes32 representation of the string.
     */
    function _toBytes32(string memory source) internal pure returns (bytes32 result) {
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
     * @notice The EXECUTOR_ROLE is required to execute this function.
     */
    function execute() external nonReentrant onlyRole(EXECUTOR_ROLE) {
        bool isExecutor = gov.checkExecutorRole(address(this));
        if (!isExecutor) revert IsNotExecutor(address(this));
        gov.setGovParams(param, data);
    }
}
