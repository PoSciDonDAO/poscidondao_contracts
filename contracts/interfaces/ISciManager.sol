// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

interface ISciManager {
    function free(uint256 amount) external;

    function getLatestUserRights(address user) external view returns (uint256);

    function getProposeLockEnd(address user) external view returns (uint256);

    function getLockedSci(address user) external view returns (uint256);

    function getTotalLockedSci() external returns (uint256);
    
    function getUserRights(
        address user,
        uint256 snapshotIndex,
        uint256 blockNum
    ) external view returns (uint256);
    
    function lock(uint256 amount) external;

    function proposed(
        address user,
        uint256 proposeLockEnd
    ) external returns (bool);

    function voted(address user, uint256 voteLockEnd) external returns (bool);
}
