// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IBanVoteWeightSource {
    function voteWeightOf(uint256 groupId, uint256 voterId) external view returns (uint256);

    function totalVoteWeight(uint256 groupId) external view returns (uint256);
}
