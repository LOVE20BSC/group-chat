// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupDefaults {
    function GROUP_ADDRESS() external view returns (address);

    function defaultGroupIdOf(address account) external view returns (uint256);
}
