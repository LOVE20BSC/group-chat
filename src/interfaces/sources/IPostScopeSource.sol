// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IPostScopeSource {
    function canPost(uint256 groupId, uint256 senderId, address senderAddress) external view returns (bool);
}
