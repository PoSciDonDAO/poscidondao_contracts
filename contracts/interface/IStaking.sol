//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IStaking {
    function freePo(uint256 amount) external;

    function freeSci(uint256 amount) external;

    function getLatestUserRights(address user) external view returns (uint256);

    function getProposalLockEndTime(address user) external view returns (uint256);

    function getStakedSci(address user) external view returns (uint256);

    function getTotalStaked() external returns (uint256);
    
    function getUserRights(
        address user,
        uint256 snapshotIndex,
        uint256 blockNum
    ) external view returns (uint256);
    
    function lockPo(uint256 amount) external;

    function lockSci(uint256 amount) external;

    function proposed(
        address user,
        uint256 proposalLockEnd
    ) external returns (bool);

    function terminate(address admin) external;

    function voted(address user, uint256 voteLockEnd) external returns (bool);
}
