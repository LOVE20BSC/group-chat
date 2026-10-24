// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IPostScopeSource} from "../IPostScopeSource.sol";

interface IGroupJoinScopeSource is IPostScopeSource {
    function GROUP_MEMBER_ADDRESS() external view returns (address);

    function GROUP_ACTION_EXECUTOR_ADDRESS() external view returns (address);
}
