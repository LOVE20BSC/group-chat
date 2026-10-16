// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupDelegate {
    function GROUP_ADDRESS() external view returns (address);

    function ownerOrDelegateIdOf(uint256 groupId, address account) external view returns (uint256);
}
