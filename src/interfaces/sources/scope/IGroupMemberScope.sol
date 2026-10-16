// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPostScopeSource} from "../IPostScopeSource.sol";

interface IGroupMemberScope is IPostScopeSource {
    error GroupMemberScopeAddressHasNoCode();

    function GROUP_MEMBER_ADDRESS() external view returns (address);
}
