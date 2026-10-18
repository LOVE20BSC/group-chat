// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";
import {IGroupChatBanList} from "./interfaces/IGroupChatBanList.sol";
import {IGroupChatDelegate} from "./interfaces/IGroupChatDelegate.sol";
import {MemberOwner} from "./MemberOwner.sol";
import {Uint256Set} from "libs/Uint256Set.sol";

contract GroupChatBanList is IGroupChatBanList {
    using Uint256Set for Uint256Set.Storage;

    address public immutable GROUP_ADMIN_ADDRESS;

    address internal immutable _groupAddress;
    address internal immutable _groupDelegateAddress;

    struct BanOperatorState {
        address operatorAddress;
        uint256 operatorId;
    }

    struct ChatState {
        Uint256Set.Storage senderIdBanList;
        mapping(uint256 => BanOperatorState) senderIdBanOperatorStates;
    }

    mapping(uint256 => ChatState) internal _states;

    constructor(address groupAdmin_) {
        if (groupAdmin_.code.length == 0) {
            revert GroupBanListAddressHasNoCode();
        }
        GROUP_ADMIN_ADDRESS = groupAdmin_;
        _groupAddress = IGroupAdmin(groupAdmin_).GROUP_ADDRESS();
        _groupDelegateAddress = IGroupAdmin(groupAdmin_).GROUP_DELEGATE_ADDRESS();
    }

    function banBySenderIds(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds) external {
        _requireOperator(groupId, operatorId);
        _setSenderIdBanTargets(groupId, operatorId, senderIds, true);
    }

    function unbanBySenderIds(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds) external {
        _requireOperator(groupId, operatorId);
        _setSenderIdBanTargets(groupId, operatorId, senderIds, false);
    }

    function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool) {
        return _states[groupId].senderIdBanList.contains(senderId);
    }

    function isSenderIdBannedBatch(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned)
    {
        Uint256Set.Storage storage banList = _states[groupId].senderIdBanList;
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
        ChatState storage state = _states[groupId];
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

    function senderIdBanListCount(uint256 groupId) external view returns (uint256) {
        return _states[groupId].senderIdBanList.count();
    }

    function senderIdBanList(uint256 groupId, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory senderIds, address[] memory operatorAddresses, uint256[] memory operatorIds)
    {
        ChatState storage state = _states[groupId];
        (senderIds,) = state.senderIdBanList.values(offset, limit, false);
        operatorAddresses = new address[](senderIds.length);
        operatorIds = new uint256[](senderIds.length);
        for (uint256 i = 0; i < senderIds.length; i++) {
            BanOperatorState storage operatorState = state.senderIdBanOperatorStates[senderIds[i]];
            operatorAddresses[i] = operatorState.operatorAddress;
            operatorIds[i] = operatorState.operatorId;
        }
    }

    function _setSenderIdBanTargets(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds, bool listed)
        internal
    {
        ChatState storage state = _states[groupId];
        for (uint256 i = 0; i < senderIds.length; i++) {
            uint256 senderId = senderIds[i];
            _requireSenderIdTarget(senderId);
            if (_setSenderIdList(state.senderIdBanList, senderId, listed)) {
                _setSenderIdBanOperatorState(state, senderId, operatorId, listed);
                emit SetSenderIdBan(groupId, msg.sender, senderId, operatorId, listed);
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

    function _setSenderIdList(Uint256Set.Storage storage set, uint256 senderId, bool listed) internal returns (bool) {
        return listed ? set.add(senderId) : set.remove(senderId);
    }

    function _requireSenderIdTarget(uint256 senderId) internal pure {
        if (senderId == 0) {
            revert TargetSenderIdZero();
        }
    }

    function _requireOperator(uint256 groupId, uint256 operatorId) internal view {
        if (IGroupChatDelegate(_groupDelegateAddress).ownerOrDelegateIdOf(groupId, msg.sender) == operatorId) {
            return;
        }
        // Load-bearing: a nonexistent operatorId collapses into the unauthorized revert instead of
        // reverting separately, so the caller cannot use the error to probe whether a member id exists.
        if (IGroupAdmin(GROUP_ADMIN_ADDRESS).isAdminId(groupId, operatorId)
            && MemberOwner.ofOrZero(_groupAddress, operatorId) == msg.sender) {
            return;
        }
        revert UnauthorizedGroupBanListManager();
    }
}
