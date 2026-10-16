// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILOVE20Join {
    function originBlocks() external view returns (uint256);

    function phaseBlocks() external view returns (uint256);

    function currentRound() external view returns (uint256);

    function amountByActionIdByAccount(address tokenAddress, uint256 actionId, address account)
        external
        view
        returns (uint256);

    function amountByAccount(address tokenAddress, address account) external view returns (uint256);
}
