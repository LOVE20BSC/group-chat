// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {ManagerBase} from "../../src/managers/ManagerBase.sol";

contract MockManager is ManagerBase {
    bool public mockPostAllowed = true;
    uint256 public mockVoteWeight = 1;

    constructor(
        address groupChat,
        address banSource,
        address beforePostPlugin,
        address afterPostPlugin,
        address actionTarget
    ) ManagerBase(groupChat, banSource, beforePostPlugin, afterPostPlugin, actionTarget) {}

    function _typeCode() internal pure override returns (string memory) {
        return "mk";
    }

    function activateMockManagedGroup() external returns (uint256 groupId) {
        groupId = _mintManagedGroup("mock_manager", GROUP_NAME_RANDOM_HEX_LENGTH, _love20TokenRequiresTestPrefix());
        _activateManagedGroup(groupId);
    }

    function setMockPostAllowed(bool postAllowed) external {
        mockPostAllowed = postAllowed;
    }

    function setMockVoteWeight(uint256 mockVoteWeightValue) external {
        mockVoteWeight = mockVoteWeightValue;
    }

    function isSenderAllowed(uint256, uint256) external view returns (bool) {
        return mockPostAllowed;
    }

    function voteWeight(uint256, uint256) external view returns (uint256) {
        return mockVoteWeight;
    }

    function totalVoteWeight(uint256) external view returns (uint256) {
        return mockVoteWeight;
    }
}
