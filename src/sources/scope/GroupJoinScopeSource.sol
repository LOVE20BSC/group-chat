// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupActionIndexes} from "@action/interfaces/IGroupActionIndexes.sol";
import {IGroupMember} from "../../interfaces/IGroupMember.sol";
import {IGroupJoinScopeSource} from "../../interfaces/sources/scope/IGroupJoinScopeSource.sol";

contract GroupJoinScopeSource is IGroupJoinScopeSource {
    address public immutable GROUP_MEMBER_ADDRESS;
    address public immutable GROUP_ACTION_EXECUTOR_ADDRESS;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupMemberAddress, address groupActionExecutorAddress) {
        GROUP_MEMBER_ADDRESS = groupMemberAddress;
        GROUP_ACTION_EXECUTOR_ADDRESS = groupActionExecutorAddress;
    }

    function isSenderAllowed(uint256 groupId, uint256 senderId) external view returns (bool) {
        if (IGroupMember(GROUP_MEMBER_ADDRESS).isMemberId(groupId, senderId)) {
            return true;
        }
        return IGroupActionIndexes(GROUP_ACTION_EXECUTOR_ADDRESS).isGroupMember(groupId, senderId);
    }
}
