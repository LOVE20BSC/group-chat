// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";
import {IGroupMember} from "./interfaces/IGroupMember.sol";
import {ILOVE20Group} from "./interfaces/external/ILOVE20Group.sol";
import {EnumerableSets} from "./libraries/EnumerableSets.sol";

contract GroupMember is IGroupMember {
    using EnumerableSets for EnumerableSets.UintSet;

    address public immutable GROUP_ADMIN_ADDRESS;
    address public immutable GROUP_ADDRESS;

    struct MemberState {
        EnumerableSets.UintSet memberIds;
    }

    mapping(uint256 => MemberState) internal _states;

    constructor(address groupAdmin_) {
        if (groupAdmin_.code.length == 0) {
            revert GroupMemberAddressHasNoCode();
        }
        GROUP_ADMIN_ADDRESS = groupAdmin_;
        GROUP_ADDRESS = IGroupAdmin(groupAdmin_).GROUP_ADDRESS();
    }

    function addMemberIds(uint256 groupId, uint256[] calldata memberIdList) external {
        uint256 operatorId = _requireAdmin(groupId);
        _setMemberIds(groupId, operatorId, memberIdList, true);
    }

    function removeMemberIds(uint256 groupId, uint256[] calldata memberIdList) external {
        uint256 operatorId = _requireAdmin(groupId);
        _setMemberIds(groupId, operatorId, memberIdList, false);
    }

    function isMemberId(uint256 groupId, uint256 memberId) external view returns (bool) {
        return _states[groupId].memberIds.contains(memberId);
    }

    function isMemberIdBatch(uint256 groupId, uint256[] calldata memberIdList)
        external
        view
        returns (bool[] memory listed)
    {
        MemberState storage state = _states[groupId];
        listed = new bool[](memberIdList.length);
        for (uint256 i = 0; i < memberIdList.length; i++) {
            listed[i] = state.memberIds.contains(memberIdList[i]);
        }
    }

    function memberIdsCount(uint256 groupId) external view returns (uint256) {
        return _states[groupId].memberIds.values.length;
    }

    function memberIds(uint256 groupId, uint256 offset, uint256 limit) external view returns (uint256[] memory) {
        return _states[groupId].memberIds.page(offset, limit);
    }

    function _setMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIdList, bool listed)
        internal
    {
        MemberState storage state = _states[groupId];
        for (uint256 i = 0; i < memberIdList.length; i++) {
            uint256 memberId = memberIdList[i];
            _requireMemberIdTarget(memberId);
            if (_setMemberId(state.memberIds, memberId, listed)) {
                emit SetMemberId(groupId, msg.sender, memberId, operatorId, listed);
            }
        }
    }

    function _setMemberId(EnumerableSets.UintSet storage set, uint256 memberId, bool listed) internal returns (bool) {
        return listed ? set.add(memberId) : set.remove(memberId);
    }

    function _requireAdmin(uint256 groupId) internal view returns (uint256 operatorId) {
        operatorId = IGroupAdmin(GROUP_ADMIN_ADDRESS).adminIdOf(groupId, msg.sender);
        if (operatorId == 0) {
            operatorId = IGroupAdmin(GROUP_ADMIN_ADDRESS).ownerOrDelegateIdOf(groupId, msg.sender);
        }
        if (operatorId == 0) {
            revert UnauthorizedGroupMemberManager();
        }
    }

    function _requireMemberIdTarget(uint256 memberId) internal view {
        if (memberId == 0) {
            revert TargetMemberIdZero();
        }
        _ownerOfOrRevert(memberId);
    }

    function _ownerOfOrRevert(uint256 groupId) internal view returns (address owner) {
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            revert GroupNotExist();
        }
    }
}
