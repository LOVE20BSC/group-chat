// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";
import {IGroupBanList} from "./interfaces/IGroupBanList.sol";
import {EnumerableSets} from "./libraries/EnumerableSets.sol";

contract GroupBanList is IGroupBanList {
    using EnumerableSets for EnumerableSets.AddressSet;
    using EnumerableSets for EnumerableSets.UintSet;

    address public immutable GROUP_ADMIN_ADDRESS;

    struct BanOperatorState {
        address operatorAddress;
        uint256 operatorId;
    }

    struct ChatState {
        EnumerableSets.AddressSet addressBanList;
        EnumerableSets.UintSet senderIdBanList;
        mapping(address => BanOperatorState) addressBanOperatorStates;
        mapping(uint256 => BanOperatorState) senderIdBanOperatorStates;
    }

    mapping(uint256 => ChatState) internal _states;

    constructor(address groupAdmin_) {
        if (groupAdmin_.code.length == 0) {
            revert GroupBanListAddressHasNoCode();
        }
        GROUP_ADMIN_ADDRESS = groupAdmin_;
    }

    function banBySenderIds(uint256 groupId, uint256[] calldata senderIds) external {
        uint256 operatorId = _requireAdmin(groupId);
        _setSenderIdBanTargets(groupId, operatorId, senderIds, true);
    }

    function unbanBySenderIds(uint256 groupId, uint256[] calldata senderIds) external {
        uint256 operatorId = _requireAdmin(groupId);
        _setSenderIdBanTargets(groupId, operatorId, senderIds, false);
    }

    function banBySenderAddresses(uint256 groupId, address[] calldata senderAddresses) external {
        uint256 operatorId = _requireAdmin(groupId);
        _setSenderAddressBanTargets(groupId, operatorId, senderAddresses, true);
    }

    function unbanBySenderAddresses(uint256 groupId, address[] calldata senderAddresses) external {
        uint256 operatorId = _requireAdmin(groupId);
        _setSenderAddressBanTargets(groupId, operatorId, senderAddresses, false);
    }

    function banBySenders(uint256 groupId, uint256[] calldata senderIds, address[] calldata senderAddresses) external {
        uint256 operatorId = _requireAdmin(groupId);
        if (senderIds.length != senderAddresses.length) {
            revert SenderPairLengthMismatch();
        }
        ChatState storage state = _states[groupId];
        for (uint256 i = 0; i < senderIds.length; i++) {
            _setSenderBanTarget(state, groupId, operatorId, senderIds[i], senderAddresses[i], true);
        }
    }

    function unbanBySenders(uint256 groupId, uint256[] calldata senderIds, address[] calldata senderAddresses)
        external
    {
        uint256 operatorId = _requireAdmin(groupId);
        if (senderIds.length != senderAddresses.length) {
            revert SenderPairLengthMismatch();
        }
        ChatState storage state = _states[groupId];
        for (uint256 i = 0; i < senderIds.length; i++) {
            _setSenderBanTarget(state, groupId, operatorId, senderIds[i], senderAddresses[i], false);
        }
    }

    function isAddressBanned(uint256 groupId, address senderAddress) external view returns (bool) {
        return _states[groupId].addressBanList.contains(senderAddress);
    }

    function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool) {
        return _states[groupId].senderIdBanList.contains(senderId);
    }

    function addressBanDetails(uint256 groupId, address[] calldata senderAddresses)
        external
        view
        returns (bool[] memory banned, address[] memory operatorAddresses, uint256[] memory operatorIds)
    {
        ChatState storage state = _states[groupId];
        banned = new bool[](senderAddresses.length);
        operatorAddresses = new address[](senderAddresses.length);
        operatorIds = new uint256[](senderAddresses.length);
        for (uint256 i = 0; i < senderAddresses.length; i++) {
            banned[i] = state.addressBanList.contains(senderAddresses[i]);
            BanOperatorState storage operatorState = state.addressBanOperatorStates[senderAddresses[i]];
            operatorAddresses[i] = operatorState.operatorAddress;
            operatorIds[i] = operatorState.operatorId;
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

    function addressBanListCount(uint256 groupId) external view returns (uint256) {
        return _states[groupId].addressBanList.values.length;
    }

    function addressBanList(uint256 groupId, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory senderAddresses, address[] memory operatorAddresses, uint256[] memory operatorIds)
    {
        ChatState storage state = _states[groupId];
        senderAddresses = state.addressBanList.page(offset, limit);
        operatorAddresses = new address[](senderAddresses.length);
        operatorIds = new uint256[](senderAddresses.length);
        for (uint256 i = 0; i < senderAddresses.length; i++) {
            BanOperatorState storage operatorState = state.addressBanOperatorStates[senderAddresses[i]];
            operatorAddresses[i] = operatorState.operatorAddress;
            operatorIds[i] = operatorState.operatorId;
        }
    }

    function senderIdBanListCount(uint256 groupId) external view returns (uint256) {
        return _states[groupId].senderIdBanList.values.length;
    }

    function senderIdBanList(uint256 groupId, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory senderIds, address[] memory operatorAddresses, uint256[] memory operatorIds)
    {
        ChatState storage state = _states[groupId];
        senderIds = state.senderIdBanList.page(offset, limit);
        operatorAddresses = new address[](senderIds.length);
        operatorIds = new uint256[](senderIds.length);
        for (uint256 i = 0; i < senderIds.length; i++) {
            BanOperatorState storage operatorState = state.senderIdBanOperatorStates[senderIds[i]];
            operatorAddresses[i] = operatorState.operatorAddress;
            operatorIds[i] = operatorState.operatorId;
        }
    }

    function isBanned(uint256 groupId, uint256 senderId, address senderAddress) external view returns (bool) {
        return _isBanned(_states[groupId], senderId, senderAddress);
    }

    function _isBanned(ChatState storage state, uint256 senderId, address senderAddress) internal view returns (bool) {
        return state.addressBanList.contains(senderAddress) || state.senderIdBanList.contains(senderId);
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
                _emitSetSenderIdBan(groupId, operatorId, senderId, listed);
            }
        }
    }

    function _setSenderAddressBanTargets(
        uint256 groupId,
        uint256 operatorId,
        address[] calldata senderAddresses,
        bool listed
    ) internal {
        ChatState storage state = _states[groupId];
        for (uint256 i = 0; i < senderAddresses.length; i++) {
            address senderAddress = senderAddresses[i];
            _requireAddressTarget(senderAddress);
            if (_setAddressList(state.addressBanList, senderAddress, listed)) {
                _setAddressBanOperatorState(state, senderAddress, operatorId, listed);
                _emitSetAddressBan(groupId, operatorId, senderAddress, listed);
            }
        }
    }

    function _setSenderBanTarget(
        ChatState storage state,
        uint256 groupId,
        uint256 operatorId,
        uint256 senderId,
        address senderAddress,
        bool listed
    ) internal {
        if (senderAddress == address(0)) {
            revert TargetAddressZero();
        }
        if (senderId == 0) {
            revert TargetSenderIdZero();
        }

        if (_setAddressList(state.addressBanList, senderAddress, listed)) {
            _setAddressBanOperatorState(state, senderAddress, operatorId, listed);
            _emitSetAddressBan(groupId, operatorId, senderAddress, listed);
        }
        if (_setSenderIdList(state.senderIdBanList, senderId, listed)) {
            _setSenderIdBanOperatorState(state, senderId, operatorId, listed);
            _emitSetSenderIdBan(groupId, operatorId, senderId, listed);
        }
    }

    function _setAddressBanOperatorState(
        ChatState storage state,
        address senderAddress,
        uint256 operatorId,
        bool listed
    ) internal {
        if (listed) {
            state.addressBanOperatorStates[senderAddress] = BanOperatorState(msg.sender, operatorId);
        } else {
            delete state.addressBanOperatorStates[senderAddress];
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

    function _setSenderIdList(EnumerableSets.UintSet storage set, uint256 senderId, bool listed)
        internal
        returns (bool)
    {
        return listed ? set.add(senderId) : set.remove(senderId);
    }

    function _setAddressList(EnumerableSets.AddressSet storage set, address targetAddress, bool listed)
        internal
        returns (bool)
    {
        return listed ? set.add(targetAddress) : set.remove(targetAddress);
    }

    function _requireSenderIdTarget(uint256 senderId) internal pure {
        if (senderId == 0) {
            revert TargetSenderIdZero();
        }
    }

    function _requireAddressTarget(address senderAddress) internal pure {
        if (senderAddress == address(0)) {
            revert TargetAddressZero();
        }
    }

    function _requireAdmin(uint256 groupId) internal view returns (uint256 operatorId) {
        operatorId = IGroupAdmin(GROUP_ADMIN_ADDRESS).adminIdOf(groupId, msg.sender);
        if (operatorId == 0) {
            operatorId = IGroupAdmin(GROUP_ADMIN_ADDRESS).ownerOrDelegateIdOf(groupId, msg.sender);
        }
        if (operatorId == 0) {
            revert UnauthorizedGroupBanListManager();
        }
    }

    function _emitSetAddressBan(uint256 groupId, uint256 operatorId, address senderAddress, bool listed) internal {
        emit SetAddressBan(groupId, msg.sender, senderAddress, operatorId, listed);
    }

    function _emitSetSenderIdBan(uint256 groupId, uint256 operatorId, uint256 senderId, bool listed) internal {
        emit SetSenderIdBan(groupId, msg.sender, senderId, operatorId, listed);
    }
}
