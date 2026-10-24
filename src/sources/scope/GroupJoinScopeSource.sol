// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupActionIndexes} from "@action/interfaces/IGroupActionIndexes.sol";
import {IGroupMember} from "../../interfaces/IGroupMember.sol";
import {IGroupJoinScopeSource} from "../../interfaces/sources/scope/IGroupJoinScopeSource.sol";

contract GroupJoinScopeSource is IGroupJoinScopeSource {
    address public immutable GROUP_MEMBER_ADDRESS;
    address public immutable GROUP_ACTION_EXECUTOR_ADDRESS;

    constructor(address groupMember_, address groupActionExecutor_) {
        GROUP_MEMBER_ADDRESS = groupMember_;
        GROUP_ACTION_EXECUTOR_ADDRESS = groupActionExecutor_;
    }

    function canPost(uint256 groupId, uint256 senderId) external view returns (bool) {
        if (IGroupMember(GROUP_MEMBER_ADDRESS).isMemberId(groupId, senderId)) {
            return true;
        }
        return IGroupActionIndexes(GROUP_ACTION_EXECUTOR_ADDRESS).isGroupMember(groupId, senderId);
    }
}
