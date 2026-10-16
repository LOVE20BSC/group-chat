// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IBanVoteWeightSource {
    function voteWeightOf(uint256 groupId, address voter) external view returns (uint256);

    function totalVoteWeight(uint256 groupId) external view returns (uint256);
}
