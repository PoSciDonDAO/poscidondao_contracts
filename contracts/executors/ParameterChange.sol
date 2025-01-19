// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGovernorParams {
    function setGovernanceParameter(bytes32 param, uint256 data) external;
}

/**
 * @title ParameterChange
 * @dev Handles execution of changes to governance parameters.
 */
contract ParameterChange is ReentrancyGuard, AccessControl {
   
    error AlreadyInitialized();
    error CannotBeZeroAddress();
    error InvalidParameter(bytes32 param);
    error FactoryAlreadySet();
    error Unauthorized(address caller);

    address public gov;
    address public governorExecutor;
    uint256 public data;
    bytes32 public param;
    string public humanReadableParam;
    address public factory;
    bool private _initialized;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    address public constant ADMIN = 0x96f67a852f8D3Bc05464C4F91F97aACE060e247A;

    event ActionExecuted(address indexed action, string indexed contractName);
    event Initialized(address gov, address governorExecutor, string param, uint256 data);
    event FactorySet(address indexed user, address newAddress);
    
    /**
     * @dev Constructor that grants DEFAULT_ADMIN_ROLE to ADMIN address
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, ADMIN);
    }

    /**
     * @dev Initializes the parameter change contract
     * @param params Encoded parameters (gov, governorExecutor, param string, data)
     */
    function initialize(bytes memory params) external {
        if (_initialized) revert AlreadyInitialized();
        if (msg.sender != factory) revert Unauthorized(msg.sender);

        (address gov_, address governorExecutor_, string memory param_, uint256 data_) = 
            abi.decode(params, (address, address, string, uint256));

        if (gov_ == address(0) || governorExecutor_ == address(0)) {
            revert CannotBeZeroAddress();
        }

        gov = gov_;
        governorExecutor = governorExecutor_;
        param = _toBytes32(param_);
        _checkValidParameter(param);
        humanReadableParam = param_;
        data = data_;
        _grantRole(GOVERNOR_ROLE, governorExecutor_);

        _initialized = true;
        emit Initialized(gov_, governorExecutor_, param_, data_);
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
     * @dev Sets the new factory contract address for ParameterChange
     * @param newFactory The address to be set as the factory contract
     */
    function setFactory(
        address newFactory
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFactory == address(0)) revert CannotBeZeroAddress();
        if (factory != address(0)) revert FactoryAlreadySet();
        factory = newFactory;
        emit FactorySet(msg.sender, newFactory);
    }

    /**
     * @dev Execute the proposal to set a governance parameter
     */
    function execute() external nonReentrant onlyRole(GOVERNOR_ROLE) {
        IGovernorParams(gov).setGovernanceParameter(param, data);
        _revokeRole(GOVERNOR_ROLE, governorExecutor);
        emit ActionExecuted(address(this), "ParameterChange");
    }
}
