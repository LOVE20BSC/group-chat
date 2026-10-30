// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChatDelegate} from "./interfaces/IGroupChatDelegate.sol";
import {MemberOwner} from "@action/MemberOwner.sol";
import {IMemberNFT} from "@core/interfaces/IMemberNFT.sol";
import {Uint256Set} from "@libs/Uint256Set.sol";

contract GroupChatDelegate is IGroupChatDelegate {
    using Uint256Set for Uint256Set.Storage;

    address public immutable GROUP_ADDRESS;

    struct DelegateState {
        uint256 delegateId;
        address ownerSnapshot;
        address delegateOwnerSnapshot;
    }

    // groupId => delegation state, valid only while both snapshots still hold
    mapping(uint256 => DelegateState) internal _delegateState;
    // delegateId => groupIds delegated to it
    mapping(uint256 => Uint256Set.Storage) internal _groupIdsByDelegateId;
    // delegateId => whether it accepts new delegations (does not affect existing ones)
    mapping(uint256 => bool) internal _delegationAcceptanceEnabledByDelegateId;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupAddress) {
        GROUP_ADDRESS = groupAddress;
    }

    modifier onlyGroupOwner(uint256 groupId) {
        if (msg.sender != _ownerOrRevertGroupNotExist(groupId)) {
            revert NotGroupOwner(groupId);
        }
        _;
    }

    modifier onlyDelegateOwner(uint256 delegateId) {
        if (IMemberNFT(GROUP_ADDRESS).ownerOf(delegateId) != msg.sender) {
            revert NotMemberOwner(delegateId);
        }
        _;
    }

    function setDelegateId(uint256 groupId, uint256 delegateId) external onlyGroupOwner(groupId) {
        address owner = _ownerOrRevertGroupNotExist(groupId);

        if (delegateId == groupId) {
            revert DelegateIsSelfGroup(groupId);
        }

        address ownerSnapshot = address(0);
        address delegateOwnerSnapshot = address(0);
        if (delegateId != 0) {
            ownerSnapshot = owner;
            delegateOwnerSnapshot = IMemberNFT(GROUP_ADDRESS).ownerOf(delegateId);
            if (!_delegationAcceptanceEnabledByDelegateId[delegateId]) {
                revert DelegateNotAcceptingNewDelegations(delegateId);
            }
        }

        DelegateState storage state = _delegateState[groupId];
        if (
            state.delegateId == delegateId && state.ownerSnapshot == ownerSnapshot
                && state.delegateOwnerSnapshot == delegateOwnerSnapshot
        ) {
            return;
        }

        uint256 prevDelegateId = state.delegateId;
        if (prevDelegateId != 0 && prevDelegateId != delegateId) {
            _groupIdsByDelegateId[prevDelegateId].remove(groupId);
        }
        if (delegateId != 0 && prevDelegateId != delegateId) {
            _groupIdsByDelegateId[delegateId].add(groupId);
        }

        address prevOwnerSnapshot = state.ownerSnapshot;
        address prevDelegateOwnerSnapshot = state.delegateOwnerSnapshot;
        state.delegateId = delegateId;
        state.ownerSnapshot = ownerSnapshot;
        state.delegateOwnerSnapshot = delegateOwnerSnapshot;
        emit DelegateChanged({
            groupId: groupId,
            delegateId: delegateId,
            owner: owner,
            ownerSnapshot: ownerSnapshot,
            delegateOwnerSnapshot: delegateOwnerSnapshot,
            prevDelegateId: prevDelegateId,
            prevOwnerSnapshot: prevOwnerSnapshot,
            prevDelegateOwnerSnapshot: prevDelegateOwnerSnapshot
        });
    }

    function clearDelegatedGroupIds(uint256 delegateId, uint256[] calldata groupIds)
        external
        onlyDelegateOwner(delegateId)
    {
        address delegateOwner = IMemberNFT(GROUP_ADDRESS).ownerOf(delegateId);

        uint256 length = groupIds.length;
        for (uint256 i = 0; i < length;) {
            DelegateState storage state = _delegateState[groupIds[i]];
            if (state.delegateId == delegateId) {
                address prevOwnerSnapshot = state.ownerSnapshot;
                address prevDelegateOwnerSnapshot = state.delegateOwnerSnapshot;
                state.delegateId = 0;
                state.ownerSnapshot = address(0);
                state.delegateOwnerSnapshot = address(0);
                _groupIdsByDelegateId[delegateId].remove(groupIds[i]);
                emit DelegationCleared({
                    groupId: groupIds[i],
                    delegateId: delegateId,
                    delegateOwner: delegateOwner,
                    prevOwnerSnapshot: prevOwnerSnapshot,
                    prevDelegateOwnerSnapshot: prevDelegateOwnerSnapshot
                });
            }

            unchecked {
                ++i;
            }
        }
    }

    function setDelegationAcceptanceEnabled(uint256 delegateId, bool enabled) external onlyDelegateOwner(delegateId) {
        address delegateOwner = IMemberNFT(GROUP_ADDRESS).ownerOf(delegateId);
        if (_delegationAcceptanceEnabledByDelegateId[delegateId] == enabled) {
            return;
        }

        _delegationAcceptanceEnabledByDelegateId[delegateId] = enabled;
        emit DelegationAcceptanceChanged({
            delegateId: delegateId,
            delegateOwner: delegateOwner,
            enabled: enabled
        });
    }

    function isDelegationAcceptanceEnabled(uint256 delegateId) external view returns (bool) {
        return _delegationAcceptanceEnabledByDelegateId[delegateId];
    }

    function effectiveDelegateId(uint256 groupId) external view returns (uint256) {
        address owner = _ownerOrRevertGroupNotExist(groupId);
        return _effectiveDelegateId(_delegateState[groupId], owner);
    }

    function effectiveDelegateIdsByGroupIds(uint256[] calldata groupIds)
        external
        view
        returns (uint256[] memory delegateIds)
    {
        uint256 length = groupIds.length;
        delegateIds = new uint256[](length);
        if (length == 0) {
            return delegateIds;
        }

        uint256 groupSupply = _groupSupply();
        for (uint256 i = 0; i < length;) {
            uint256 groupId = groupIds[i];
            _validateGroupExists(groupId, groupSupply);

            DelegateState storage state = _delegateState[groupId];
            if (state.delegateId != 0) {
                delegateIds[i] = _effectiveDelegateId(state, _ownerOrRevertGroupNotExist(groupId));
            }

            unchecked {
                ++i;
            }
        }
    }

    function delegatedGroupIds(uint256 delegateId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory groupIdList, bool[] memory isEffective, uint256 totalCount)
    {
        (groupIdList, totalCount) = _groupIdsByDelegateId[delegateId].values(offset, limit, reverse);
        uint256 length = groupIdList.length;
        isEffective = new bool[](length);
        for (uint256 i = 0; i < length;) {
            address owner = _ownerOrRevertGroupNotExist(groupIdList[i]);
            isEffective[i] = _effectiveDelegateId(_delegateState[groupIdList[i]], owner) == delegateId;
            unchecked {
                ++i;
            }
        }
    }

    function ownerOrDelegateId(uint256 groupId, address operatorAddress) external view returns (uint256) {
        return _ownerOrDelegateId(groupId, operatorAddress);
    }

    function _ownerOrDelegateId(uint256 groupId, address operatorAddress) internal view returns (uint256) {
        address owner = _ownerOrRevertGroupNotExist(groupId);
        if (operatorAddress == owner) {
            return groupId;
        }

        uint256 delegateId = _effectiveDelegateId(_delegateState[groupId], owner);
        if (delegateId != 0) {
            address delegateOwner = _memberOwnerOrZero(delegateId);
            if (delegateOwner != address(0) && operatorAddress == delegateOwner) {
                return delegateId;
            }
        }
        return 0;
    }

    function _effectiveDelegateId(DelegateState storage state, address owner) internal view returns (uint256) {
        if (state.ownerSnapshot != owner) {
            return 0;
        }
        uint256 delegateId = state.delegateId;
        if (delegateId == 0) {
            return 0;
        }
        address delegateOwner = _memberOwnerOrZero(delegateId);
        if (delegateOwner == address(0) || state.delegateOwnerSnapshot != delegateOwner) {
            return 0;
        }
        return delegateId;
    }

    function _validateGroupExists(uint256 groupId, uint256 groupSupply) internal pure {
        // Group IDs start at 1 and are never burned, so totalSupply is the upper bound of minted IDs.
        if (groupId == 0 || groupId > groupSupply) {
            revert GroupNotExist(groupId);
        }
    }

    function _groupSupply() internal view returns (uint256) {
        return IMemberNFT(GROUP_ADDRESS).totalSupply();
    }

    function _ownerOrRevertGroupNotExist(uint256 groupId) internal view returns (address owner) {
        owner = MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId);
        if (owner == address(0)) {
            revert GroupNotExist(groupId);
        }
    }

    function _memberOwnerOrZero(uint256 memberId) internal view returns (address) {
        return MemberOwner.ownerOrZero(GROUP_ADDRESS, memberId);
    }
}
