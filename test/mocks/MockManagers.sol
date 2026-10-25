// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {ManagerBase} from "../../src/managers/ManagerBase.sol";

contract MockManager is ManagerBase {
    bool public postAllowed = true;
    uint256 public voteWeight = 1;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_
    ) ManagerBase(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, actionTarget_) {}

    function _typeCode() internal pure override returns (string memory) {
        return "mk";
    }

    function activateMockManagedGroup() external returns (uint256 groupId) {
        groupId = _mintManagedGroup("mock_manager", GROUP_NAME_RANDOM_HEX_LENGTH, _love20TokenRequiresTestPrefix());
        _activateManagedGroup(groupId);
    }

    function setMockPostAllowed(bool postAllowed_) external {
        postAllowed = postAllowed_;
    }

    function setMockVoteWeight(uint256 voteWeight_) external {
        voteWeight = voteWeight_;
    }

    function canPost(uint256, uint256) external view returns (bool) {
        return postAllowed;
    }

    function voteWeightOf(uint256, uint256) external view returns (uint256) {
        return voteWeight;
    }

    function totalVoteWeight(uint256) external view returns (uint256) {
        return voteWeight;
    }
}
