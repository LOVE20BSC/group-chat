// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";
import {IGroupChatDelegate} from "./interfaces/IGroupChatDelegate.sol";
import {MemberOwner} from "@action/MemberOwner.sol";
import {IMemberNFT} from "@core/interfaces/IMemberNFT.sol";
import {Uint256Set} from "@libs/Uint256Set.sol";

contract GroupAdmin is IGroupAdmin {
    using Uint256Set for Uint256Set.Storage;

    address public immutable GROUP_DELEGATE_ADDRESS;
    address public immutable GROUP_ADDRESS;
    uint256 public immutable MAX_ADMIN_IDS;

    struct AdminState {
        Uint256Set.Storage adminIds;
        mapping(uint256 => address) groupOwnerSnapshots;
        mapping(uint256 => address) adminOwnerSnapshots;
    }

    mapping(uint256 => AdminState) internal _states;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupDelegate_, uint256 maxAdminIds_) {
        address love20Group = IGroupChatDelegate(groupDelegate_).GROUP_ADDRESS();
        GROUP_DELEGATE_ADDRESS = groupDelegate_;
        GROUP_ADDRESS = love20Group;
        MAX_ADMIN_IDS = maxAdminIds_;
    }

    function addAdmins(uint256 groupId, uint256 operatorId, uint256[] calldata adminIds_)
        external
        onlyOwnerOrDelegate(groupId, operatorId)
    {
        _validateAdminIds(adminIds_);
        _requireAdminIdsLimit(_states[groupId], groupId, adminIds_);

        AdminState storage state = _states[groupId];
        address groupOwnerSnapshot = _groupOwnerOfOrRevert(groupId);
        for (uint256 i = 0; i < adminIds_.length; i++) {
            _addAdminId(state, groupId, operatorId, groupOwnerSnapshot, adminIds_[i]);
        }
    }

    function removeAdmins(uint256 groupId, uint256 operatorId, uint256[] calldata adminIds_)
        external
        onlyOwnerOrDelegate(groupId, operatorId)
    {
        _validateAdminIds(adminIds_);

        AdminState storage state = _states[groupId];
        for (uint256 i = 0; i < adminIds_.length; i++) {
            uint256 adminId = adminIds_[i];
            _removeAdminId(state, groupId, operatorId, adminId);
        }
    }

    function isAdminId(uint256 groupId, uint256 adminId) external view returns (bool) {
        AdminState storage state = _states[groupId];
        return state.adminIds.contains(adminId) && _isEffectiveAdminId(state, groupId, adminId);
    }

    function adminIds(uint256 groupId) external view returns (uint256[] memory ids, bool[] memory isEffective) {
        AdminState storage state = _states[groupId];
        (ids,) = state.adminIds.values(0, type(uint256).max, false);
        uint256 length = ids.length;
        isEffective = new bool[](length);
        for (uint256 i = 0; i < length; i++) {
            isEffective[i] = _isEffectiveAdminId(state, groupId, ids[i]);
        }
    }

    function _addAdminId(
        AdminState storage state,
        uint256 groupId,
        uint256 operatorId,
        address groupOwnerSnapshot,
        uint256 adminId
    ) internal {
        address adminOwnerSnapshot = IMemberNFT(GROUP_ADDRESS).ownerOf(adminId);
        address prevGroupOwnerSnapshot = state.groupOwnerSnapshots[adminId];
        address prevAdminOwnerSnapshot = state.adminOwnerSnapshots[adminId];
        bool snapshotChanged =
            prevGroupOwnerSnapshot != groupOwnerSnapshot || prevAdminOwnerSnapshot != adminOwnerSnapshot;
        if (snapshotChanged) {
            state.groupOwnerSnapshots[adminId] = groupOwnerSnapshot;
            state.adminOwnerSnapshots[adminId] = adminOwnerSnapshot;
        }

        bool added = state.adminIds.add(adminId);
        bool prevListed = !added;
        if (!added && !snapshotChanged) {
            return;
        }

        emit AdminChanged({
            groupId: groupId,
            adminId: adminId,
            operatorId: operatorId,
            operator: msg.sender,
            listed: true,
            groupOwnerSnapshot: groupOwnerSnapshot,
            adminOwnerSnapshot: adminOwnerSnapshot,
            prevListed: prevListed,
            prevGroupOwnerSnapshot: prevGroupOwnerSnapshot,
            prevAdminOwnerSnapshot: prevAdminOwnerSnapshot
        });
    }

    function _removeAdminId(
        AdminState storage state,
        uint256 groupId,
        uint256 operatorId,
        uint256 adminId
    ) internal {
        if (!state.adminIds.remove(adminId)) {
            return;
        }

        address prevGroupOwnerSnapshot = state.groupOwnerSnapshots[adminId];
        address prevAdminOwnerSnapshot = state.adminOwnerSnapshots[adminId];
        delete state.groupOwnerSnapshots[adminId];
        delete state.adminOwnerSnapshots[adminId];
        emit AdminChanged({
            groupId: groupId,
            adminId: adminId,
            operatorId: operatorId,
            operator: msg.sender,
            listed: false,
            groupOwnerSnapshot: address(0),
            adminOwnerSnapshot: address(0),
            prevListed: true,
            prevGroupOwnerSnapshot: prevGroupOwnerSnapshot,
            prevAdminOwnerSnapshot: prevAdminOwnerSnapshot
        });
    }

    function _validateAdminIds(uint256[] calldata adminIds_) internal view {
        for (uint256 i = 0; i < adminIds_.length; i++) {
            IMemberNFT(GROUP_ADDRESS).ownerOf(adminIds_[i]);
            for (uint256 j = 0; j < i; j++) {
                if (adminIds_[i] == adminIds_[j]) {
                    revert DuplicateMemberId(adminIds_[i]);
                }
            }
        }
    }

    function _newAdminIdsCount(AdminState storage state, uint256[] calldata adminIds_)
        internal
        view
        returns (uint256 count)
    {
        for (uint256 i = 0; i < adminIds_.length; i++) {
            if (!state.adminIds.contains(adminIds_[i])) {
                count++;
            }
        }
    }

    function _requireAdminIdsLimit(AdminState storage state, uint256 groupId, uint256[] calldata adminIds_)
        internal
        view
    {
        uint256 count = state.adminIds.count() + _newAdminIdsCount(state, adminIds_);
        if (count > MAX_ADMIN_IDS) {
            revert AdminIdsLimitExceeded(groupId, count, MAX_ADMIN_IDS);
        }
    }

    function _isEffectiveAdminId(AdminState storage state, uint256 groupId, uint256 adminId)
        internal
        view
        returns (bool)
    {
        address ownerSnapshot = state.groupOwnerSnapshots[adminId];
        address adminOwnerSnapshot = state.adminOwnerSnapshots[adminId];
        return ownerSnapshot != address(0) && adminOwnerSnapshot != address(0)
            && MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId) == ownerSnapshot
            && MemberOwner.ownerOrZero(GROUP_ADDRESS, adminId) == adminOwnerSnapshot;
    }

    modifier onlyOwnerOrDelegate(
        uint256 groupId,
        uint256 operatorId
    ) {
        uint256 resolvedOperatorId =
            IGroupChatDelegate(GROUP_DELEGATE_ADDRESS).ownerOrDelegateIdOf(groupId, msg.sender);
        if (resolvedOperatorId == 0 || resolvedOperatorId != operatorId) {
            revert NotGroupOperator(groupId, operatorId);
        }
        _;
    }

    function _groupOwnerOfOrRevert(uint256 groupId) internal view returns (address owner) {
        owner = MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId);
        if (owner == address(0)) {
            revert GroupNotExist(groupId);
        }
    }
}
