// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IExtensionCenter {
    function launchAddress() external view returns (address);

    function stakeAddress() external view returns (address);

    function joinAddress() external view returns (address);

    function voteAddress() external view returns (address);

    function submitAddress() external view returns (address);

    function isAccountJoined(address tokenAddress, uint256 actionId, address account) external view returns (bool);
}
