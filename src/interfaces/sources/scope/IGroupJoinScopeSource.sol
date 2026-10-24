// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IPostScopeSource} from "../IPostScopeSource.sol";

interface IGroupJoinScopeSourceErrors {
    error GroupMemberNotContract(address dependency);
    error GroupActionExecutorNotContract(address dependency);
}

interface IGroupJoinScopeSource is IPostScopeSource, IGroupJoinScopeSourceErrors {
    function GROUP_MEMBER_ADDRESS() external view returns (address);

    function GROUP_ACTION_EXECUTOR_ADDRESS() external view returns (address);
}
