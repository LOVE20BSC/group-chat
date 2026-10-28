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

    constructor(address groupAddress_) {
        GROUP_ADDRESS = groupAddress_;
    }

    function setDelegateId(uint256 groupId, uint256 delegateId) external {
        address owner = _groupOwnerOfOrRevert(groupId);
        if (msg.sender != owner) {
            revert NotGroupOwner(groupId);
        }
        if (delegateId == groupId) {
            revert DelegateIsSelfGroup(groupId);
        }
        if (delegateId != 0) {
            _memberOwnerOfOrRevert(delegateId);
        }

        DelegateState storage state = _states[groupId];
        address targetOwnerSnapshot = delegateId == 0 ? address(0) : owner;
        if (state.delegateId == delegateId && state.ownerSnapshot == targetOwnerSnapshot) {
            return;
        }

        state.delegateId = delegateId;
        state.ownerSnapshot = targetOwnerSnapshot;
        // No event here: mock-only events land in out/ ABI and fail script/check-events.py (no family),
        // and this mock cannot supply DelegateChanged's snapshots faithfully. Delegate event coverage
        // lives on the real GroupChatDelegate.
    }

    function ownerOrDelegateIdOf(uint256 groupId, address account) external view returns (uint256) {
        return _ownerOrDelegateIdOf(groupId, account);
    }

    function delegateIdOf(uint256 groupId) external view returns (uint256) {
        return _delegateIdOf(_states[groupId], _groupOwnerOfOrRevert(groupId));
    }

    function _ownerOrDelegateIdOf(uint256 groupId, address account) internal view returns (uint256) {
        address owner = _groupOwnerOfOrRevert(groupId);
        if (account == owner) {
            return groupId;
        }

        uint256 delegateId = _delegateIdOf(_states[groupId], owner);
        if (delegateId != 0 && account == _memberOwnerOfOrZero(delegateId)) {
            return delegateId;
        }
        return 0;
    }

    function _delegateIdOf(DelegateState storage state, address owner) internal view returns (uint256) {
        if (state.ownerSnapshot != owner) {
            return 0;
        }
        return state.delegateId;
    }

    function _groupOwnerOfOrRevert(uint256 groupId) internal view returns (address owner) {
        try IMemberNFT(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            revert GroupNotExist(groupId);
        }
    }

    function _memberOwnerOfOrRevert(uint256 memberId) internal view returns (address) {
        return IMemberNFT(GROUP_ADDRESS).ownerOf(memberId);
    }

    function _memberOwnerOfOrZero(uint256 memberId) internal view returns (address) {
        try IMemberNFT(GROUP_ADDRESS).ownerOf(memberId) returns (address resolved) {
            return resolved;
        } catch {
            return address(0);
        }
    }
}
