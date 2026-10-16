// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILOVE20Vote {
    function currentRound() external view returns (uint256);

    function votesNumByAccountByActionId(address tokenAddress, uint256 round, address account, uint256 actionId)
        external
        view
        returns (uint256);

    function votedActionIdsCount(address tokenAddress, uint256 round) external view returns (uint256);

    function votedActionIdsAtIndex(address tokenAddress, uint256 round, uint256 index)
        external
        view
        returns (uint256);
}
