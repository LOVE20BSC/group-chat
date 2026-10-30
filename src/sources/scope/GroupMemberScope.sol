// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupMember} from "../../interfaces/IGroupMember.sol";
import {IGroupMemberScope} from "../../interfaces/sources/scope/IGroupMemberScope.sol";

contract GroupMemberScope is IGroupMemberScope {
    address public immutable GROUP_MEMBER_ADDRESS;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupMemberAddress) {
        GROUP_MEMBER_ADDRESS = groupMemberAddress;
    }

    function isSenderAllowed(uint256 groupId, uint256 senderId) external view returns (bool) {
        return IGroupMember(GROUP_MEMBER_ADDRESS).isMemberId(groupId, senderId);
    }
}
