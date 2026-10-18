// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IPostScopeSource} from "../IPostScopeSource.sol";

interface IGroupMemberScope is IPostScopeSource {
    function GROUP_MEMBER_ADDRESS() external view returns (address);

    error GroupMemberScopeAddressHasNoCode();
}
