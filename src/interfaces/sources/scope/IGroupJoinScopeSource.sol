// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPostScopeSource} from "../IPostScopeSource.sol";

interface IGroupJoinScopeSource is IPostScopeSource {
    error GroupJoinScopeSourceAddressHasNoCode();

    function GROUP_MEMBER_ADDRESS() external view returns (address);

    function GROUP_JOIN_ADDRESS() external view returns (address);
}
