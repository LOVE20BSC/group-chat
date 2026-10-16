// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IGroupDelegate} from "./interfaces/IGroupDelegate.sol";

contract GroupDelegate is IGroupDelegate {
    address public immutable GROUP_ADDRESS;

    struct DelegateState {
        uint256 delegateId;
        address ownerSnapshot;
        address delegateOwnerSnapshot;
    }

    mapping(uint256 => DelegateState) internal _delegateStates;
    mapping(uint256 => uint256[]) internal _groupIdsByDelegateId;
    mapping(uint256 => mapping(uint256 => uint256)) internal _groupIdIndexPlusOneByDelegateId;
    mapping(uint256 => bool) internal _delegatorWhitelistEnabled;
    mapping(uint256 => uint256[]) internal _allowedDelegatorGroupIdsByDelegateId;
    mapping(uint256 => mapping(uint256 => uint256)) internal _allowedDelegatorIndexPlusOneByDelegateId;

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
            _removeDelegatedGroupId(prevRawDelegateId, groupId);
        }
        if (delegateId != 0 && prevRawDelegateId != delegateId) {
            _addDelegatedGroupId(delegateId, groupId);
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
        for (uint256 i; i < length;) {
            DelegateState storage state = _delegateStates[groupIds[i]];
            if (state.delegateId == delegateId) {
                state.delegateId = 0;
                state.ownerSnapshot = address(0);
                state.delegateOwnerSnapshot = address(0);
                _removeDelegatedGroupId(delegateId, groupIds[i]);
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
        for (uint256 i; i < length;) {
            uint256 groupId = groupIds[i];
            _validateGroupExists(groupId, groupSupply);
            if (groupId == delegateId) {
                revert DelegateIdCannotBeGroupId();
            }

            bool changed;
            if (allowed) {
                changed = _addAllowedDelegatorGroupId(delegateId, groupId);
            } else {
                changed = _removeAllowedDelegatorGroupId(delegateId, groupId);
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

        uint256[] storage storedGroupIds = _allowedDelegatorGroupIdsByDelegateId[delegateId];
        total = storedGroupIds.length;
        if (offset >= total || limit == 0) {
            return (new uint256[](0), total);
        }

        uint256 remaining = total - offset;
        uint256 length = limit < remaining ? limit : remaining;
        groupIds = new uint256[](length);
        for (uint256 i; i < length;) {
            groupIds[i] = storedGroupIds[offset + i];
            unchecked {
                ++i;
            }
        }
    }

    function allowedDelegatorGroupIdsCount(uint256 delegateId) external view returns (uint256) {
        _validateGroupExists(delegateId);
        return _allowedDelegatorGroupIdsByDelegateId[delegateId].length;
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
        for (uint256 i; i < length;) {
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

        uint256[] storage storedGroupIds = _groupIdsByDelegateId[delegateId];
        total = storedGroupIds.length;
        if (offset >= total || limit == 0) {
            return (new uint256[](0), new bool[](0), total);
        }

        uint256 remaining = total - offset;
        uint256 length = limit < remaining ? limit : remaining;
        groupIds = new uint256[](length);
        isEffective = new bool[](length);

        for (uint256 i; i < length;) {
            uint256 groupId = storedGroupIds[offset + i];
            groupIds[i] = groupId;
            isEffective[i] = _isEffectiveDelegateId(groupId, delegateId);
            unchecked {
                ++i;
            }
        }
    }

    function delegatedGroupIdsCount(uint256 delegateId) external view returns (uint256) {
        _validateGroupExists(delegateId);
        return _groupIdsByDelegateId[delegateId].length;
    }

    function ownerOrDelegateIdOf(uint256 groupId, address account) external view returns (uint256) {
        return _ownerOrDelegateIdOf(groupId, account);
    }

    function isOwnerOrDelegate(uint256 groupId, address account) external view returns (bool) {
        return _ownerOrDelegateIdOf(groupId, account) != 0;
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
        return _allowedDelegatorIndexPlusOneByDelegateId[delegateId][groupId] != 0;
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
        return IERC721Enumerable(GROUP_ADDRESS).totalSupply();
    }

    function _addDelegatedGroupId(uint256 delegateId, uint256 groupId) internal {
        if (_groupIdIndexPlusOneByDelegateId[delegateId][groupId] != 0) {
            return;
        }

        _groupIdsByDelegateId[delegateId].push(groupId);
        _groupIdIndexPlusOneByDelegateId[delegateId][groupId] = _groupIdsByDelegateId[delegateId].length;
    }

    function _removeDelegatedGroupId(uint256 delegateId, uint256 groupId) internal {
        uint256 indexPlusOne = _groupIdIndexPlusOneByDelegateId[delegateId][groupId];
        if (indexPlusOne == 0) {
            return;
        }

        uint256[] storage groupIds = _groupIdsByDelegateId[delegateId];
        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = groupIds.length - 1;
        if (index != lastIndex) {
            uint256 lastGroupId = groupIds[lastIndex];
            groupIds[index] = lastGroupId;
            _groupIdIndexPlusOneByDelegateId[delegateId][lastGroupId] = indexPlusOne;
        }

        groupIds.pop();
        delete _groupIdIndexPlusOneByDelegateId[delegateId][groupId];
    }

    function _addAllowedDelegatorGroupId(uint256 delegateId, uint256 groupId) internal returns (bool) {
        if (_allowedDelegatorIndexPlusOneByDelegateId[delegateId][groupId] != 0) {
            return false;
        }

        _allowedDelegatorGroupIdsByDelegateId[delegateId].push(groupId);
        _allowedDelegatorIndexPlusOneByDelegateId[delegateId][groupId] =
            _allowedDelegatorGroupIdsByDelegateId[delegateId].length;
        return true;
    }

    function _removeAllowedDelegatorGroupId(uint256 delegateId, uint256 groupId) internal returns (bool) {
        uint256 indexPlusOne = _allowedDelegatorIndexPlusOneByDelegateId[delegateId][groupId];
        if (indexPlusOne == 0) {
            return false;
        }

        uint256[] storage groupIds = _allowedDelegatorGroupIdsByDelegateId[delegateId];
        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = groupIds.length - 1;
        if (index != lastIndex) {
            uint256 lastGroupId = groupIds[lastIndex];
            groupIds[index] = lastGroupId;
            _allowedDelegatorIndexPlusOneByDelegateId[delegateId][lastGroupId] = indexPlusOne;
        }

        groupIds.pop();
        delete _allowedDelegatorIndexPlusOneByDelegateId[delegateId][groupId];
        return true;
    }

    function _ownerOfOrRevert(uint256 groupId) internal view returns (address owner) {
        try IERC721(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            revert GroupNotExist();
        }
    }
}
