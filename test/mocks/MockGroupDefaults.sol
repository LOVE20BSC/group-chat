// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupDefaults} from "../../src/interfaces/external/IGroupDefaults.sol";
import {ILOVE20Group} from "../../src/interfaces/external/ILOVE20Group.sol";

contract MockGroupDefaults is IGroupDefaults {
    error GroupNotExist();
    error SenderNotGroupOwner();
    error DefaultGroupIdAlreadySet(uint256 groupId);
    error DefaultGroupIdNotSet();

    event SetDefaultGroupId(address indexed account, uint256 indexed groupId);
    event ClearDefaultGroupId(address indexed account, uint256 indexed prevGroupId);

    address public immutable GROUP_ADDRESS;

    mapping(address => uint256) internal _defaultGroupIds;

    constructor(address groupAddress_) {
        GROUP_ADDRESS = groupAddress_;
    }

    function setDefaultGroupId(uint256 groupId) external {
        address senderOwner = _ownerOfOrRevert(groupId);
        if (msg.sender != senderOwner) {
            revert SenderNotGroupOwner();
        }
        if (_defaultGroupIds[msg.sender] == groupId) {
            revert DefaultGroupIdAlreadySet(groupId);
        }
        _defaultGroupIds[msg.sender] = groupId;
        emit SetDefaultGroupId(msg.sender, groupId);
    }

    function clearDefaultGroupId() external {
        uint256 prevGroupId = _defaultGroupIds[msg.sender];
        if (prevGroupId == 0) {
            revert DefaultGroupIdNotSet();
        }
        delete _defaultGroupIds[msg.sender];
        emit ClearDefaultGroupId(msg.sender, prevGroupId);
    }

    function defaultGroupIdOf(address account) external view returns (uint256) {
        return _effectiveDefaultGroupId(account);
    }

    function defaultGroupsOf(address[] calldata accounts)
        external
        view
        returns (uint256[] memory groupIds, string[] memory groupNames)
    {
        uint256 length = accounts.length;
        groupIds = new uint256[](length);
        groupNames = new string[](length);

        for (uint256 i = 0; i < length; i++) {
            groupIds[i] = _effectiveDefaultGroupId(accounts[i]);
        }
    }

    function _ownerOfOrRevert(uint256 groupId) internal view returns (address owner) {
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            revert GroupNotExist();
        }
    }

    function _effectiveDefaultGroupId(address account) internal view returns (uint256 groupId) {
        groupId = _defaultGroupIds[account];
        if (groupId == 0) {
            return 0;
        }
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address owner) {
            if (owner == account) {
                return groupId;
            }
        } catch {}
        return 0;
    }
}
