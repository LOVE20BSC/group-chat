// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";
import {IGroupChatBanList} from "./interfaces/IGroupChatBanList.sol";
import {IGroupChatDelegate} from "./interfaces/IGroupChatDelegate.sol";
import {MemberOwner} from "@action/MemberOwner.sol";
import {Uint256Set} from "@libs/Uint256Set.sol";

contract GroupChatBanList is IGroupChatBanList {
    using Uint256Set for Uint256Set.Storage;

    address public immutable GROUP_ADMIN_ADDRESS;

    address public immutable GROUP_ADDRESS;
    address public immutable GROUP_DELEGATE_ADDRESS;

    struct BanOperatorState {
        address operatorAddress;
        uint256 operatorId;
    }

    struct ChatState {
        Uint256Set.Storage senderIdBanList;
        // groupId => senderId => operator that last banned it
        mapping(uint256 => BanOperatorState) senderIdBanOperatorStates;
    }

    // groupId => ban list state
    mapping(uint256 => ChatState) internal _chatState;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupAdminAddress) {
        GROUP_ADMIN_ADDRESS = groupAdminAddress;
        GROUP_ADDRESS = IGroupAdmin(groupAdminAddress).GROUP_ADDRESS();
        GROUP_DELEGATE_ADDRESS = IGroupAdmin(groupAdminAddress).GROUP_DELEGATE_ADDRESS();
    }

    function banBySenderIds(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds)
        external
        onlyOperator(groupId, operatorId)
    {
        _setSenderIdBanTargets(groupId, operatorId, senderIds, true);
    }

    function unbanBySenderIds(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds)
        external
        onlyOperator(groupId, operatorId)
    {
        _setSenderIdBanTargets(groupId, operatorId, senderIds, false);
    }

    function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool) {
        return _chatState[groupId].senderIdBanList.contains(senderId);
    }

    function isSenderIdBannedBatch(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned)
    {
        Uint256Set.Storage storage banList = _chatState[groupId].senderIdBanList;
        banned = new bool[](senderIds.length);
        for (uint256 i = 0; i < senderIds.length; i++) {
            banned[i] = banList.contains(senderIds[i]);
        }
    }

    function senderIdBanDetails(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned, address[] memory operatorAddresses, uint256[] memory operatorIds)
    {
        ChatState storage state = _chatState[groupId];
        banned = new bool[](senderIds.length);
        operatorAddresses = new address[](senderIds.length);
        operatorIds = new uint256[](senderIds.length);
        for (uint256 i = 0; i < senderIds.length; i++) {
            banned[i] = state.senderIdBanList.contains(senderIds[i]);
            BanOperatorState storage operatorState = state.senderIdBanOperatorStates[senderIds[i]];
            operatorAddresses[i] = operatorState.operatorAddress;
            operatorIds[i] = operatorState.operatorId;
        }
    }

    function senderIdBanList(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (
            uint256[] memory senderIdList,
            address[] memory operatorAddresses,
            uint256[] memory operatorIds,
            uint256 totalCount
        )
    {
        ChatState storage state = _chatState[groupId];
        (senderIdList, totalCount) = state.senderIdBanList.values(offset, limit, reverse);
        uint256 length = senderIdList.length;
        operatorAddresses = new address[](length);
        operatorIds = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            BanOperatorState storage operatorState = state.senderIdBanOperatorStates[senderIdList[i]];
            operatorAddresses[i] = operatorState.operatorAddress;
            operatorIds[i] = operatorState.operatorId;
        }
    }

    function _setSenderIdBanTargets(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds, bool listed)
        internal
    {
        ChatState storage state = _chatState[groupId];
        for (uint256 i = 0; i < senderIds.length; i++) {
            uint256 senderId = senderIds[i];
            _requireSenderIdTarget(senderId);
            for (uint256 j = 0; j < i; j++) {
                if (senderIds[j] == senderId) {
                    revert DuplicateMemberId(senderId);
                }
            }
            bool changed = listed ? state.senderIdBanList.add(senderId) : state.senderIdBanList.remove(senderId);
            if (changed) {
                _setSenderIdBanOperatorState(state, senderId, operatorId, listed);
                emit SenderBanChanged({
                    groupId: groupId,
                    targetSenderId: senderId,
                    operatorId: operatorId,
                    operator: msg.sender,
                    listed: listed
                });
            }
        }
    }

    function _setSenderIdBanOperatorState(ChatState storage state, uint256 senderId, uint256 operatorId, bool listed)
        internal
    {
        if (listed) {
            state.senderIdBanOperatorStates[senderId] = BanOperatorState(msg.sender, operatorId);
        } else {
            delete state.senderIdBanOperatorStates[senderId];
        }
    }

    function _requireSenderIdTarget(uint256 senderId) internal pure {
        if (senderId == 0) {
            revert ZeroTargetSenderId();
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
