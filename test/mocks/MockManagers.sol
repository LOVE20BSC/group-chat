// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseManager} from "../../src/managers/BaseManager.sol";

contract MockManager is BaseManager {
    bool public postAllowed = true;
    uint256 public voteWeight = 1;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address extensionCenter_
    ) BaseManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, extensionCenter_) {}

    function activateMockManagedGroup() external returns (uint256 groupId) {
        groupId = _mintManagedGroup("mock_manager");
        _activateManagedGroup(groupId);
    }

    function setMockPostAllowed(bool postAllowed_) external {
        postAllowed = postAllowed_;
    }

    function setMockVoteWeight(uint256 voteWeight_) external {
        voteWeight = voteWeight_;
    }

    function canPost(uint256, uint256, address) external view returns (bool) {
        return postAllowed;
    }

    function voteWeightOf(uint256, address) external view returns (uint256) {
        return voteWeight;
    }

    function totalVoteWeight(uint256) external view returns (uint256) {
        return voteWeight;
    }
}
