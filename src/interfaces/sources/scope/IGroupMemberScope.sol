// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IPostScopeSource} from "../IPostScopeSource.sol";

interface IGroupMemberScopeErrors {
    error GroupMemberNotContract(address dependency);
}

interface IGroupMemberScope is IPostScopeSource, IGroupMemberScopeErrors {
    function GROUP_MEMBER_ADDRESS() external view returns (address);
}
