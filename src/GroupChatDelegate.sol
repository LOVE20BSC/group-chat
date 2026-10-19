// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChatDelegate} from "./interfaces/IGroupChatDelegate.sol";
import {MemberOwner} from "./MemberOwner.sol";
import {IMemberNFT} from "core/src/interfaces/IMemberNFT.sol";
import {Uint256Set} from "libs/Uint256Set.sol";

contract GroupChatDelegate is IGroupChatDelegate {
    using Uint256Set for Uint256Set.Storage;

    address public immutable GROUP_ADDRESS;

    struct DelegateState {
        uint256 delegateId;
        address ownerSnapshot;
        address delegateOwnerSnapshot;
    }

    mapping(uint256 => DelegateState) internal _delegateStates;
    mapping(uint256 => Uint256Set.Storage) internal _groupIdsByDelegateId;
    mapping(uint256 => bool) internal _delegatorWhitelistEnabled;
    mapping(uint256 => Uint256Set.Storage) internal _allowedDelegatorGroupIdsByDelegateId;

    constructor(address groupAddress_) {
        if (groupAddress_ == address(0)) {
            revert InvalidAddress();
        }

        GROUP_ADDRESS = groupAddress_;
    }

    function setDelegateId(uint256 groupId, uint256 delegateId) external {
        address owner = _ownerOfOrRevert(groupId);
        if (msg.sender != owner) {
            revert SenderNotGroupOwner();
        }

        DelegateState storage state = _delegateStates[groupId];
        address targetOwnerSnapshot = delegateId == 0 ? address(0) : owner;
        address targetDelegateOwnerSnapshot = delegateId == 0 ? address(0) : _ownerOfOrRevert(delegateId);
        if (
            state.delegateId == delegateId && state.ownerSnapshot == targetOwnerSnapshot
                && state.delegateOwnerSnapshot == targetDelegateOwnerSnapshot
        ) {
            return;
        }

        _validateDelegateId(groupId, delegateId);
        if (!_canDelegateTo(groupId, delegateId)) {
            revert DelegatorGroupIdNotAllowed();
        }

        uint256 prevDelegateId = _delegateIdOf(groupId, state, owner);
        uint256 prevRawDelegateId = state.delegateId;
        if (prevRawDelegateId != 0 && prevRawDelegateId != delegateId) {
            _groupIdsByDelegateId[prevRawDelegateId].remove(groupId);
        }
        if (delegateId != 0 && prevRawDelegateId != delegateId) {
            _groupIdsByDelegateId[delegateId].add(groupId);
        }

        state.delegateId = delegateId;
        state.ownerSnapshot = targetOwnerSnapshot;
        state.delegateOwnerSnapshot = targetDelegateOwnerSnapshot;
        emit SetDelegateId(groupId, owner, delegateId, prevDelegateId);
    }

    function clearDelegatedGroupIds(uint256 delegateId, uint256[] calldata groupIds) external {
        address delegateOwner = _ownerOfOrRevert(delegateId);
        if (msg.sender != delegateOwner) {
            revert SenderNotDelegateOwner();
        }

        uint256 length = groupIds.length;
        for (uint256 i = 0; i < length;) {
            DelegateState storage state = _delegateStates[groupIds[i]];
            if (state.delegateId == delegateId) {
                state.delegateId = 0;
                state.ownerSnapshot = address(0);
                state.delegateOwnerSnapshot = address(0);
                _groupIdsByDelegateId[delegateId].remove(groupIds[i]);
                emit ClearDelegatedGroupId(groupIds[i], delegateId, delegateOwner);
            }

            unchecked {
                ++i;
            }
        }
    }

    function setDelegatorWhitelistEnabled(uint256 delegateId, bool enabled) external {
        address delegateOwner = _ownerOfOrRevert(delegateId);
        if (msg.sender != delegateOwner) {
            revert SenderNotDelegateOwner();
        }
        if (_delegatorWhitelistEnabled[delegateId] == enabled) {
            return;
        }

        _delegatorWhitelistEnabled[delegateId] = enabled;
        emit SetDelegatorWhitelistEnabled(delegateId, delegateOwner, enabled);
    }

    function setAllowedDelegatorGroupIds(uint256 delegateId, uint256[] calldata groupIds, bool allowed) external {
        address delegateOwner = _ownerOfOrRevert(delegateId);
        if (msg.sender != delegateOwner) {
            revert SenderNotDelegateOwner();
        }

        uint256 length = groupIds.length;
        if (length == 0) {
            return;
        }

        uint256 groupSupply = _groupSupply();
        for (uint256 i = 0; i < length;) {
            uint256 groupId = groupIds[i];
            _validateGroupExists(groupId, groupSupply);
            if (groupId == delegateId) {
                revert DelegateIdCannotBeGroupId();
            }

            bool changed;
            if (allowed) {
                changed = _allowedDelegatorGroupIdsByDelegateId[delegateId].add(groupId);
            } else {
                changed = _allowedDelegatorGroupIdsByDelegateId[delegateId].remove(groupId);
            }
            if (changed) {
                emit SetAllowedDelegatorGroupId(delegateId, groupId, delegateOwner, allowed);
            }

            unchecked {
                ++i;
            }
        }
    }

    function isDelegatorWhitelistEnabled(uint256 delegateId) external view returns (bool) {
        _validateGroupExists(delegateId);
        return _delegatorWhitelistEnabled[delegateId];
    }

    function canSetDelegateTo(uint256 groupId, uint256 delegateId) external view returns (bool) {
        uint256 groupSupply = _groupSupply();
        _validateGroupExists(groupId, groupSupply);
        if (delegateId == 0) {
            return true;
        }
        if (delegateId == groupId) {
            return false;
        }
        _validateGroupExists(delegateId, groupSupply);
        return _canDelegateTo(groupId, delegateId);
    }

    function allowedDelegatorGroupIds(uint256 delegateId, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory groupIds, uint256 total)
    {
        _validateGroupExists(delegateId);
        return _allowedDelegatorGroupIdsByDelegateId[delegateId].values(offset, limit, false);
    }

    function allowedDelegatorGroupIdsCount(uint256 delegateId) external view returns (uint256) {
        _validateGroupExists(delegateId);
        return _allowedDelegatorGroupIdsByDelegateId[delegateId].count();
    }

    function delegateIdOf(uint256 groupId) external view returns (uint256) {
        address owner = _ownerOfOrRevert(groupId);
        return _delegateIdOf(groupId, _delegateStates[groupId], owner);
    }

    function delegateIdsOf(uint256[] calldata groupIds) external view returns (uint256[] memory delegateIds) {
        uint256 length = groupIds.length;
        delegateIds = new uint256[](length);
        if (length == 0) {
            return delegateIds;
        }

        uint256 groupSupply = _groupSupply();
        for (uint256 i = 0; i < length;) {
            uint256 groupId = groupIds[i];
            _validateGroupExists(groupId, groupSupply);

            DelegateState storage state = _delegateStates[groupId];
            if (state.delegateId != 0) {
                delegateIds[i] = _delegateIdOf(groupId, state, _ownerOfOrRevert(groupId));
            }

            unchecked {
                ++i;
            }
        }
    }

    function delegatedGroupIds(uint256 delegateId, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory groupIds, bool[] memory isEffective, uint256 total)
    {
        _validateGroupExists(delegateId);

        (groupIds, total) = _groupIdsByDelegateId[delegateId].values(offset, limit, false);
        uint256 length = groupIds.length;
        isEffective = new bool[](length);
        for (uint256 i = 0; i < length;) {
            isEffective[i] = _isEffectiveDelegateId(groupIds[i], delegateId);
            unchecked {
                ++i;
            }
        }
    }

    function delegatedGroupIdsCount(uint256 delegateId) external view returns (uint256) {
        _validateGroupExists(delegateId);
        return _groupIdsByDelegateId[delegateId].count();
    }

    function ownerOrDelegateIdOf(uint256 groupId, address account) external view returns (uint256) {
        return _ownerOrDelegateIdOf(groupId, account);
    }

    function _ownerOrDelegateIdOf(uint256 groupId, address account) internal view returns (uint256) {
        address owner = _ownerOfOrRevert(groupId);
        if (account == owner) {
            return groupId;
        }

        uint256 delegateId = _delegateIdOf(groupId, _delegateStates[groupId], owner);
        if (delegateId != 0 && account == _ownerOfOrRevert(delegateId)) {
            return delegateId;
        }
        return 0;
    }

    function _canDelegateTo(uint256 groupId, uint256 delegateId) internal view returns (bool) {
        if (delegateId == 0 || !_delegatorWhitelistEnabled[delegateId]) {
            return true;
        }
        return _allowedDelegatorGroupIdsByDelegateId[delegateId].contains(groupId);
    }

    function _isEffectiveDelegateId(uint256 groupId, uint256 delegateId) internal view returns (bool) {
        address owner = _ownerOfOrRevert(groupId);
        return _delegateIdOf(groupId, _delegateStates[groupId], owner) == delegateId;
    }

    function _delegateIdOf(uint256 groupId, DelegateState storage state, address owner)
        internal
        view
        returns (uint256)
    {
        if (state.ownerSnapshot != owner) {
            return 0;
        }
        uint256 delegateId = state.delegateId;
        if (delegateId == 0) {
            return 0;
        }
        if (state.delegateOwnerSnapshot != _ownerOfOrRevert(delegateId)) {
            return 0;
        }
        if (!_canDelegateTo(groupId, delegateId)) {
            return 0;
        }
        return delegateId;
    }

    function _validateDelegateId(uint256 groupId, uint256 delegateId) internal view {
        if (delegateId == 0) {
            return;
        }
        if (delegateId == groupId) {
            revert DelegateIdCannotBeGroupId();
        }
        _validateGroupExists(delegateId);
    }

    function _validateGroupExists(uint256 groupId) internal view {
        _validateGroupExists(groupId, _groupSupply());
    }

    function _validateGroupExists(uint256 groupId, uint256 groupSupply) internal pure {
        // Group IDs start at 1 and are never burned, so totalSupply is the upper bound of minted IDs.
        if (groupId == 0 || groupId > groupSupply) {
            revert GroupNotExist();
        }
    }

    function _groupSupply() internal view returns (uint256) {
        return IMemberNFT(GROUP_ADDRESS).totalSupply();
    }

    function _ownerOfOrRevert(uint256 groupId) internal view returns (address owner) {
        owner = MemberOwner.ofOrZero(GROUP_ADDRESS, groupId);
        if (owner == address(0)) {
            revert GroupNotExist();
        }
    }
}
