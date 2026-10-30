// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";
import {IGroupChatDelegate} from "./interfaces/IGroupChatDelegate.sol";
import {IGroupMember} from "./interfaces/IGroupMember.sol";
import {MemberOwner} from "@action/MemberOwner.sol";
import {IMemberNFT} from "@core/interfaces/IMemberNFT.sol";
import {Uint256Set} from "@libs/Uint256Set.sol";

contract GroupMember is IGroupMember {
    using Uint256Set for Uint256Set.Storage;

    address public immutable GROUP_ADMIN_ADDRESS;
    address public immutable GROUP_ADDRESS;

    address public immutable GROUP_DELEGATE_ADDRESS;

    struct MemberState {
        Uint256Set.Storage memberIds;
    }

    // groupId => member state
    mapping(uint256 => MemberState) internal _memberState;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupAdminAddress) {
        GROUP_ADMIN_ADDRESS = groupAdminAddress;
        GROUP_ADDRESS = IGroupAdmin(groupAdminAddress).GROUP_ADDRESS();
        GROUP_DELEGATE_ADDRESS = IGroupAdmin(groupAdminAddress).GROUP_DELEGATE_ADDRESS();
    }

    function addMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIdList)
        external
        onlyOperator(groupId, operatorId)
    {
        _setMemberIds(groupId, operatorId, memberIdList, true);
    }

    function removeMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIdList)
        external
        onlyOperator(groupId, operatorId)
    {
        _setMemberIds(groupId, operatorId, memberIdList, false);
    }

    function isMemberId(uint256 groupId, uint256 memberId) external view returns (bool) {
        return _memberState[groupId].memberIds.contains(memberId);
    }

    function isMemberIdBatch(uint256 groupId, uint256[] calldata checkedMemberIds)
        external
        view
        returns (bool[] memory listed)
    {
        MemberState storage state = _memberState[groupId];
        listed = new bool[](checkedMemberIds.length);
        for (uint256 i = 0; i < checkedMemberIds.length; i++) {
            listed[i] = state.memberIds.contains(checkedMemberIds[i]);
        }
    }

    function memberIds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory memberIdList, uint256 totalCount)
    {
        (memberIdList, totalCount) = _memberState[groupId].memberIds.values(offset, limit, reverse);
    }

    function _setMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIdList, bool listed)
        internal
    {
        MemberState storage state = _memberState[groupId];
        for (uint256 i = 0; i < memberIdList.length; i++) {
            uint256 memberId = memberIdList[i];
            IMemberNFT(GROUP_ADDRESS).ownerOf(memberId);
            for (uint256 j = 0; j < i; j++) {
                if (memberIdList[j] == memberId) {
                    revert DuplicateMemberId(memberId);
                }
            }
            bool changed = listed ? state.memberIds.add(memberId) : state.memberIds.remove(memberId);
            if (changed) {
                emit MemberStatusChanged({
                    groupId: groupId,
                    memberId: memberId,
                    operatorId: operatorId,
                    operator: msg.sender,
                    listed: listed
                });
            }
        }
    }

    modifier onlyOperator(
        uint256 groupId,
        uint256 operatorId
    ) {
        if (!_isOperator(groupId, operatorId)) {
            revert NotGroupOperator(groupId, operatorId);
        }
        _;
    }

    function _isOperator(uint256 groupId, uint256 operatorId) private view returns (bool) {
        uint256 resolvedOperatorId =
            IGroupChatDelegate(GROUP_DELEGATE_ADDRESS).ownerOrDelegateId(groupId, msg.sender);
        if (operatorId != 0 && resolvedOperatorId == operatorId) {
            return true;
        }
        // Load-bearing: a nonexistent operatorId collapses into the unauthorized revert instead of
        // reverting separately, so the caller cannot use the error to probe whether a member id exists.
        if (operatorId != 0 && IGroupAdmin(GROUP_ADMIN_ADDRESS).isAdminId(groupId, operatorId)
            && MemberOwner.ownerOrZero(GROUP_ADDRESS, operatorId) == msg.sender) {
            return true;
        }
        return false;
    }
}
