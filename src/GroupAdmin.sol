// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";

import {IGroupDefaults} from "./interfaces/external/IGroupDefaults.sol";
import {IGroupDelegate} from "./interfaces/external/IGroupDelegate.sol";
import {ILOVE20Group} from "./interfaces/external/ILOVE20Group.sol";
import {EnumerableSets} from "./libraries/EnumerableSets.sol";

contract GroupAdmin is IGroupAdmin {
    using EnumerableSets for EnumerableSets.UintSet;

    address public immutable GROUP_DEFAULTS_ADDRESS;
    address public immutable GROUP_DELEGATE_ADDRESS;
    address public immutable GROUP_ADDRESS;
    uint256 public immutable MAX_ADMIN_IDS;

    struct AdminState {
        EnumerableSets.UintSet adminIds;
        mapping(uint256 => address) groupOwnerSnapshots;
        mapping(uint256 => address) adminOwnerSnapshots;
    }

    mapping(uint256 => AdminState) internal _states;

    constructor(address groupDefaults_, address groupDelegate_, uint256 maxAdminIds_) {
        if (maxAdminIds_ == 0) {
            revert MaxAdminIdsZero();
        }
        _requireCode(groupDefaults_);
        _requireCode(groupDelegate_);

        address love20Group = IGroupDefaults(groupDefaults_).GROUP_ADDRESS();
        if (IGroupDelegate(groupDelegate_).GROUP_ADDRESS() != love20Group) {
            revert GroupDelegateGroupMismatch();
        }
        _requireCode(love20Group);

        GROUP_DEFAULTS_ADDRESS = groupDefaults_;
        GROUP_DELEGATE_ADDRESS = groupDelegate_;
        GROUP_ADDRESS = love20Group;
        MAX_ADMIN_IDS = maxAdminIds_;
    }

    function addAdmins(uint256 groupId, uint256[] calldata adminIdList) external {
        uint256 operatorId = ownerOrDelegateIdOf(groupId, msg.sender);
        if (operatorId == 0) {
            revert UnauthorizedGroupAdminManager();
        }
        _validateAdminIds(adminIdList);

        AdminState storage state = _states[groupId];
        if (state.adminIds.values.length + _newAdminIdsCount(state, adminIdList) > MAX_ADMIN_IDS) {
            revert AdminIdsLimitExceeded();
        }

        address groupOwnerSnapshot = _ownerOfOrRevert(groupId);
        for (uint256 i = 0; i < adminIdList.length; i++) {
            uint256 adminId = adminIdList[i];
            address adminOwnerSnapshot = _ownerOfOrRevert(adminId);
            bool snapshotChanged;
            if (state.groupOwnerSnapshots[adminId] != groupOwnerSnapshot) {
                state.groupOwnerSnapshots[adminId] = groupOwnerSnapshot;
                snapshotChanged = true;
            }
            if (state.adminOwnerSnapshots[adminId] != adminOwnerSnapshot) {
                state.adminOwnerSnapshots[adminId] = adminOwnerSnapshot;
                snapshotChanged = true;
            }
            if (snapshotChanged) {
                emit SetAdminSnapshot(groupId, msg.sender, adminId, operatorId, groupOwnerSnapshot, adminOwnerSnapshot);
            }
            if (state.adminIds.add(adminId)) {
                emit SetAdmin(groupId, msg.sender, adminId, operatorId, true);
            }
        }
    }

    function removeAdmins(uint256 groupId, uint256[] calldata adminIdList) external {
        uint256 operatorId = ownerOrDelegateIdOf(groupId, msg.sender);
        if (operatorId == 0) {
            revert UnauthorizedGroupAdminManager();
        }
        _validateAdminIds(adminIdList);

        AdminState storage state = _states[groupId];
        for (uint256 i = 0; i < adminIdList.length; i++) {
            uint256 adminId = adminIdList[i];
            if (!state.adminIds.remove(adminId)) {
                continue;
            }
            delete state.groupOwnerSnapshots[adminId];
            delete state.adminOwnerSnapshots[adminId];
            emit SetAdmin(groupId, msg.sender, adminId, operatorId, false);
        }
    }

    function adminIdOf(uint256 groupId, address account) public view returns (uint256 adminId) {
        AdminState storage state = _states[groupId];
        adminId = IGroupDefaults(GROUP_DEFAULTS_ADDRESS).defaultGroupIdOf(account);
        if (
            adminId == 0 || !state.adminIds.contains(adminId) || !_isEffectiveAdminId(state, groupId, adminId)
                || state.adminOwnerSnapshots[adminId] != account || _tryOwnerOf(adminId) != account
        ) {
            return 0;
        }
    }

    function ownerOrDelegateIdOf(uint256 groupId, address account) public view returns (uint256 operatorId) {
        return IGroupDelegate(GROUP_DELEGATE_ADDRESS).ownerOrDelegateIdOf(groupId, account);
    }

    function isAdminId(uint256 groupId, uint256 adminId) external view returns (bool) {
        AdminState storage state = _states[groupId];
        return state.adminIds.contains(adminId) && _isEffectiveAdminId(state, groupId, adminId);
    }

    function adminIds(uint256 groupId) external view returns (uint256[] memory ids, bool[] memory isEffective) {
        AdminState storage state = _states[groupId];
        ids = state.adminIds.values;
        uint256 length = ids.length;
        isEffective = new bool[](length);
        for (uint256 i = 0; i < length; i++) {
            isEffective[i] = _isEffectiveAdminId(state, groupId, ids[i]);
        }
    }

    function _validateAdminIds(uint256[] calldata adminIdList) internal view {
        for (uint256 i = 0; i < adminIdList.length; i++) {
            _ownerOfOrRevert(adminIdList[i]);
            for (uint256 j = 0; j < i; j++) {
                if (adminIdList[i] == adminIdList[j]) {
                    revert DuplicateAdminId();
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

    function _isEffectiveAdminId(AdminState storage state, uint256 groupId, uint256 adminId)
        internal
        view
        returns (bool)
    {
        address ownerSnapshot = state.groupOwnerSnapshots[adminId];
        address adminOwnerSnapshot = state.adminOwnerSnapshots[adminId];
        return ownerSnapshot != address(0) && adminOwnerSnapshot != address(0) && _tryOwnerOf(groupId) == ownerSnapshot
            && _tryOwnerOf(adminId) == adminOwnerSnapshot;
    }

    function _requireCode(address target) internal view {
        if (target.code.length == 0) {
            revert GroupAdminAddressHasNoCode();
        }
    }

    function _ownerOfOrRevert(uint256 groupId) internal view returns (address owner) {
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            revert GroupNotExist();
        }
    }

    function _tryOwnerOf(uint256 groupId) internal view returns (address owner) {
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            return address(0);
        }
    }
}
