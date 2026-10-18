// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

contract MockPhase {
    uint256 public ORIGIN_BLOCKS;
    uint256 public ORIGIN_PHASE_BLOCKS;

    constructor(uint256 originBlocks_, uint256 phaseBlocks_) {
        ORIGIN_BLOCKS = originBlocks_;
        ORIGIN_PHASE_BLOCKS = phaseBlocks_;
    }

    function setPhase(uint256 originBlocks_, uint256 phaseBlocks_) external {
        ORIGIN_BLOCKS = originBlocks_;
        ORIGIN_PHASE_BLOCKS = phaseBlocks_;
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
