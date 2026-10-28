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

    address internal immutable _groupDelegateAddress;

    struct MemberState {
        Uint256Set.Storage memberIds;
    }

    mapping(uint256 => MemberState) internal _states;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupAdmin_) {
        GROUP_ADMIN_ADDRESS = groupAdmin_;
        GROUP_ADDRESS = IGroupAdmin(groupAdmin_).GROUP_ADDRESS();
        _groupDelegateAddress = IGroupAdmin(groupAdmin_).GROUP_DELEGATE_ADDRESS();
    }

    function addMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIds_)
        external
        onlyOperator(groupId, operatorId)
    {
        _setMemberIds(groupId, operatorId, memberIds_, true);
    }

    function removeMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIds_)
        external
        onlyOperator(groupId, operatorId)
    {
        _setMemberIds(groupId, operatorId, memberIds_, false);
    }

    function isMemberId(uint256 groupId, uint256 memberId) external view returns (bool) {
        return _states[groupId].memberIds.contains(memberId);
    }

    function isMemberIdBatch(uint256 groupId, uint256[] calldata memberIds_)
        external
        view
        returns (bool[] memory listed)
    {
        MemberState storage state = _states[groupId];
        listed = new bool[](memberIds_.length);
        for (uint256 i = 0; i < memberIds_.length; i++) {
            listed[i] = state.memberIds.contains(memberIds_[i]);
        }
    }

    function memberIdsCount(uint256 groupId) external view returns (uint256) {
        return _states[groupId].memberIds.count();
    }

    function memberIds(uint256 groupId, uint256 offset, uint256 limit) external view returns (uint256[] memory) {
        (uint256[] memory page,) = _states[groupId].memberIds.values(offset, limit, false);
        return page;
    }

    function _setMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIds_, bool listed)
        internal
    {
        MemberState storage state = _states[groupId];
        for (uint256 i = 0; i < memberIds_.length; i++) {
            uint256 memberId = memberIds_[i];
            IMemberNFT(GROUP_ADDRESS).ownerOf(memberId);
            for (uint256 j = 0; j < i; j++) {
                if (memberIds_[j] == memberId) {
                    revert DuplicateMemberId(memberId);
                }
            }
            bool changed = listed ? state.memberIds.add(memberId) : state.memberIds.remove(memberId);
            if (changed) {
                emit MemberStatusChanged(groupId, memberId, operatorId, msg.sender, listed);
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
            IGroupChatDelegate(_groupDelegateAddress).ownerOrDelegateIdOf(groupId, msg.sender);
        if (operatorId != 0 && resolvedOperatorId == operatorId) {
            return true;
        }
        // Load-bearing: a nonexistent operatorId collapses into the unauthorized revert instead of
        // reverting separately, so the caller cannot use the error to probe whether a member id exists.
        if (operatorId != 0 && IGroupAdmin(GROUP_ADMIN_ADDRESS).isAdminId(groupId, operatorId)
            && MemberOwner.ofOrZero(GROUP_ADDRESS, operatorId) == msg.sender) {
            return true;
        }
        return false;
    }
}
