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
        // groupId => adminId => group owner address at the time the admin was added
        mapping(uint256 => address) groupOwnerSnapshots;
        // groupId => adminId => admin NFT owner address at the time the admin was added
        mapping(uint256 => address) adminOwnerSnapshots;
    }

    // groupId => admin state
    mapping(uint256 => AdminState) internal _adminState;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupDelegateAddress, uint256 maxAdminIds) {
        address love20Group = IGroupChatDelegate(groupDelegateAddress).GROUP_ADDRESS();
        GROUP_DELEGATE_ADDRESS = groupDelegateAddress;
        GROUP_ADDRESS = love20Group;
        MAX_ADMIN_IDS = maxAdminIds;
    }

    function addAdmins(uint256 groupId, uint256 operatorId, uint256[] calldata adminIdList)
        external
        onlyOwnerOrDelegate(groupId, operatorId)
    {
        _validateAdminIds(adminIdList);
        _requireAdminIdsLimit(_adminState[groupId], groupId, adminIdList);

        AdminState storage state = _adminState[groupId];
        address groupOwnerSnapshot = _groupOwnerOrRevert(groupId);
        for (uint256 i = 0; i < adminIdList.length; i++) {
            _addAdminId(state, groupId, operatorId, groupOwnerSnapshot, adminIdList[i]);
        }
    }

    function removeAdmins(uint256 groupId, uint256 operatorId, uint256[] calldata adminIdList)
        external
        onlyOwnerOrDelegate(groupId, operatorId)
    {
        _validateAdminIds(adminIdList);

        AdminState storage state = _adminState[groupId];
        for (uint256 i = 0; i < adminIdList.length; i++) {
            uint256 adminId = adminIdList[i];
            _removeAdminId(state, groupId, operatorId, adminId);
        }
    }

    function isAdminId(uint256 groupId, uint256 adminId) external view returns (bool) {
        AdminState storage state = _adminState[groupId];
        return state.adminIds.contains(adminId) && _isEffectiveAdminId(state, groupId, adminId);
    }

    function adminIds(uint256 groupId) external view returns (uint256[] memory adminIdList, bool[] memory isEffective) {
        AdminState storage state = _adminState[groupId];
        (adminIdList,) = state.adminIds.values(0, type(uint256).max, false);
        uint256 length = adminIdList.length;
        isEffective = new bool[](length);
        for (uint256 i = 0; i < length; i++) {
            isEffective[i] = _isEffectiveAdminId(state, groupId, adminIdList[i]);
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

    function _validateAdminIds(uint256[] calldata adminIdList) internal view {
        for (uint256 i = 0; i < adminIdList.length; i++) {
            IMemberNFT(GROUP_ADDRESS).ownerOf(adminIdList[i]);
            for (uint256 j = 0; j < i; j++) {
                if (adminIdList[i] == adminIdList[j]) {
                    revert DuplicateMemberId(adminIdList[i]);
                }
            }
        }
    }

    function _newAdminIdsCount(AdminState storage state, uint256[] calldata adminIdList)
        internal
        view
        returns (uint256 count)
    {
        for (uint256 i = 0; i < adminIdList.length; i++) {
            if (!state.adminIds.contains(adminIdList[i])) {
                count++;
            }
        }
    }

    function _requireAdminIdsLimit(AdminState storage state, uint256 groupId, uint256[] calldata adminIdList)
        internal
        view
    {
        uint256 count = state.adminIds.count() + _newAdminIdsCount(state, adminIdList);
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
            IGroupChatDelegate(GROUP_DELEGATE_ADDRESS).ownerOrDelegateId(groupId, msg.sender);
        if (resolvedOperatorId == 0 || resolvedOperatorId != operatorId) {
            revert NotGroupOperator(groupId, operatorId);
        }
        _;
    }

    function _groupOwnerOrRevert(uint256 groupId) internal view returns (address owner) {
        owner = MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId);
        if (owner == address(0)) {
            revert GroupNotExist(groupId);
        }
    }
}
