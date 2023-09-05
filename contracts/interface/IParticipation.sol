//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IParticipation {
    function push(address user, uint256[] memory ids, uint256[] memory amounts) external;
    function pull(address user, uint256[] memory ids, uint256[] memory amounts) external;
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids) external returns (uint256[] memory);
    function mint(address participant) external;
}