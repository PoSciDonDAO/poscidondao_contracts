//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IStaking {
    function free(address src, address user, uint256 amount) external;

    function getLatestUserRights(address user) external view returns (uint256);

    function getStakedSci(address user) external view returns (uint256);

    function getTotalStaked() external returns (uint256);

    function getUserRights(
        address user,
        uint256 snapshotIndex,
        uint256 blockNum
    ) external view returns (uint256);

    function lock(address src, address user, uint256 amount) external;

    function terminate(address admin) external;

    function voted(address user, uint256 voteLockEnd) external returns (bool);
}
