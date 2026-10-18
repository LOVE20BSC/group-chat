// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IMemberNFT} from "core/src/interfaces/IMemberNFT.sol";

contract MockGroupDelegate {
    error GroupNotExist();
    error SenderNotGroupOwner();
    error DelegateIdCannotBeGroupId();

    event SetDelegateId(
        uint256 indexed groupId, address indexed owner, uint256 indexed delegateId, uint256 prevDelegateId
    );

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
        address owner = _ownerOfOrRevert(groupId);
        if (msg.sender != owner) {
            revert SenderNotGroupOwner();
        }
        if (delegateId == groupId) {
            revert DelegateIdCannotBeGroupId();
        }
        if (delegateId != 0) {
            _ownerOfOrRevert(delegateId);
        }

        DelegateState storage state = _states[groupId];
        address targetOwnerSnapshot = delegateId == 0 ? address(0) : owner;
        if (state.delegateId == delegateId && state.ownerSnapshot == targetOwnerSnapshot) {
            return;
        }

        uint256 prevDelegateId = _delegateIdOf(state, owner);
        state.delegateId = delegateId;
        state.ownerSnapshot = targetOwnerSnapshot;
        emit SetDelegateId(groupId, owner, delegateId, prevDelegateId);
    }

    function ownerOrDelegateIdOf(uint256 groupId, address account) external view returns (uint256) {
        return _ownerOrDelegateIdOf(groupId, account);
    }

    function delegateIdOf(uint256 groupId) external view returns (uint256) {
        return _delegateIdOf(_states[groupId], _ownerOfOrRevert(groupId));
    }

    function _ownerOrDelegateIdOf(uint256 groupId, address account) internal view returns (uint256) {
        address owner = _ownerOfOrRevert(groupId);
        if (account == owner) {
            return groupId;
        }

        uint256 delegateId = _delegateIdOf(_states[groupId], owner);
        if (delegateId != 0 && account == _ownerOfOrRevert(delegateId)) {
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

    function _ownerOfOrRevert(uint256 groupId) internal view returns (address owner) {
        try IMemberNFT(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            revert GroupNotExist();
        }
    }
}
