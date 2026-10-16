// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILOVE20Group {
    function LOVE20_TOKEN_ADDRESS() external view returns (address);

    function MAX_GROUP_NAME_LENGTH() external view returns (uint256);

    function mint(string calldata groupName) external returns (uint256 tokenId, uint256 mintCost);

    function calculateMintCost(string memory groupName) external view returns (uint256);

    function isGroupNameUsed(string calldata groupName) external view returns (bool);

    // GroupChat assumes token IDs are minted consecutively from 1 and are never burned.
    function totalSupply() external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address owner);
}
