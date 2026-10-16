// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupMember} from "../../interfaces/IGroupMember.sol";
import {IGroupJoin} from "../../interfaces/external/IGroupJoin.sol";
import {IGroupJoinScopeSource} from "../../interfaces/sources/scope/IGroupJoinScopeSource.sol";

contract GroupJoinScopeSource is IGroupJoinScopeSource {
    address public immutable GROUP_MEMBER_ADDRESS;
    address public immutable GROUP_JOIN_ADDRESS;

    constructor(address groupMember_, address groupJoin_) {
        if (groupMember_.code.length == 0 || groupJoin_.code.length == 0) {
            revert GroupJoinScopeSourceAddressHasNoCode();
        }
        GROUP_MEMBER_ADDRESS = groupMember_;
        GROUP_JOIN_ADDRESS = groupJoin_;
    }

    function canPost(uint256 groupId, uint256 senderId, address senderAddress) external view returns (bool) {
        if (IGroupMember(GROUP_MEMBER_ADDRESS).isMemberId(groupId, senderId)) {
            return true;
        }
        return IGroupJoin(GROUP_JOIN_ADDRESS).gTokenAddressesByGroupIdByAccountCount(groupId, senderAddress) != 0;
    }
}
