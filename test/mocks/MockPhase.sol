// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

contract MockPhase {
    uint256 public ORIGIN_BLOCKS;
    uint256 public ORIGIN_PHASE_BLOCKS;

    constructor(uint256 originBlocks, uint256 phaseBlocks) {
        ORIGIN_BLOCKS = originBlocks;
        ORIGIN_PHASE_BLOCKS = phaseBlocks;
    }

    function setPhase(uint256 originBlocks, uint256 phaseBlocks) external {
        ORIGIN_BLOCKS = originBlocks;
        ORIGIN_PHASE_BLOCKS = phaseBlocks;
    }

    function currentPhase() external view returns (uint256) {
        return phaseAtBlock(block.number);
    }

    function phaseAtBlock(uint256 blockNumber) public view returns (uint256) {
        if (blockNumber < ORIGIN_BLOCKS) {
            return 0;
        }
        return (blockNumber - ORIGIN_BLOCKS) / ORIGIN_PHASE_BLOCKS + 1;
    }
}
