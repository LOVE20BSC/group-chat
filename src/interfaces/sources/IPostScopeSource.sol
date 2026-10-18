// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IPostScopeSource {
    function canPost(uint256 groupId, uint256 senderId) external view returns (bool);
}
