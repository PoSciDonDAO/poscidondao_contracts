//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IStaking {
    function getUserRights(address _user, uint256 _snapshotIndex, uint256 _blockNum) external view returns (uint256);
    function getSnapshot(address _user, uint256 _snapshotNum) external view returns (uint256, uint256);
    function lock(address _src, address _user, uint256 _amount) external;
    function free(address _src, address _user, uint256 _amount) external;
    function getTotalStaked() external returns (uint256);
    function voted(address _user, uint256 _voteLockEnd) external returns (bool);
}