// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IPostBanSource {
    function isBanned(uint256 groupId, uint256 senderId, address senderAddress) external view returns (bool);
}
