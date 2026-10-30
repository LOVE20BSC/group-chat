// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IMemberNFT} from "@core/interfaces/IMemberNFT.sol";

contract MockGroupDelegate {
    error GroupNotExist(uint256 groupId);
    error NotGroupOwner(uint256 groupId);
    error DelegateIsSelfGroup(uint256 groupId);

    address public immutable GROUP_ADDRESS;

    struct DelegateState {
        uint256 delegateId;
        address ownerSnapshot;
    }

    mapping(uint256 => DelegateState) internal _states;

    constructor(address groupAddress) {
        GROUP_ADDRESS = groupAddress;
    }

    function setDelegateId(uint256 groupId, uint256 delegateId) external {
        address owner = _groupOwnerOrRevert(groupId);
        if (msg.sender != owner) {
            revert NotGroupOwner(groupId);
        }
        if (delegateId == groupId) {
            revert DelegateIsSelfGroup(groupId);
        }
        if (delegateId != 0) {
            _memberOwnerOrRevert(delegateId);
        }

        DelegateState storage state = _states[groupId];
        address ownerSnapshot = delegateId == 0 ? address(0) : owner;
        if (state.delegateId == delegateId && state.ownerSnapshot == ownerSnapshot) {
            return;
        }

        state.delegateId = delegateId;
        state.ownerSnapshot = ownerSnapshot;
        // No event here: mock-only events land in out/ ABI and fail script/check-events.py (no family),
        // and this mock cannot supply DelegateChanged's snapshots faithfully. Delegate event coverage
        // lives on the real GroupChatDelegate.
    }

    function ownerOrDelegateId(uint256 groupId, address operatorAddress) external view returns (uint256) {
        return _ownerOrDelegateId(groupId, operatorAddress);
    }

    function effectiveDelegateId(uint256 groupId) external view returns (uint256) {
        return _effectiveDelegateId(_states[groupId], _groupOwnerOrRevert(groupId));
    }

    function _ownerOrDelegateId(uint256 groupId, address operatorAddress) internal view returns (uint256) {
        address owner = _groupOwnerOrRevert(groupId);
        if (operatorAddress == owner) {
            return groupId;
        }

        uint256 delegateId = _effectiveDelegateId(_states[groupId], owner);
        if (delegateId != 0 && operatorAddress == _memberOwnerOrZero(delegateId)) {
            return delegateId;
        }
        return 0;
    }

    function _effectiveDelegateId(DelegateState storage state, address owner) internal view returns (uint256) {
        if (state.ownerSnapshot != owner) {
            return 0;
        }
        return state.delegateId;
    }

    function _groupOwnerOrRevert(uint256 groupId) internal view returns (address owner) {
        try IMemberNFT(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            revert GroupNotExist(groupId);
        }
    }

    function _memberOwnerOrRevert(uint256 memberId) internal view returns (address) {
        return IMemberNFT(GROUP_ADDRESS).ownerOf(memberId);
    }

    function _memberOwnerOrZero(uint256 memberId) internal view returns (address) {
        try IMemberNFT(GROUP_ADDRESS).ownerOf(memberId) returns (address resolved) {
            return resolved;
        } catch {
            return address(0);
        }
    }
}
