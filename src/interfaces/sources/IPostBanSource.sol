// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IPostBanSource {
    function isBanned(uint256 groupId, uint256 senderId) external view returns (bool);
}
