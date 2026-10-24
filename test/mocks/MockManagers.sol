// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {BaseManager} from "../../src/managers/BaseManager.sol";

contract MockManager is BaseManager {
    bool public postAllowed = true;
    uint256 public voteWeight = 1;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_
    ) BaseManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, actionTarget_) {}

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external
        view
        returns (bytes4)
    {
        return _onERC721ReceivedFromMint(operator, from, tokenId);
    }

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
