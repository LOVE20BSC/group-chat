// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupDelegate} from "../../src/interfaces/external/IGroupDelegate.sol";
import {ILOVE20Group} from "../../src/interfaces/external/ILOVE20Group.sol";

contract MockGroupDelegate is IGroupDelegate {
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
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            revert GroupNotExist();
        }
    }
}
