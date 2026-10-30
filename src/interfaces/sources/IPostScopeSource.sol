// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IPostScopeSource {
    function isSenderAllowed(uint256 groupId, uint256 senderId) external view returns (bool);
}
