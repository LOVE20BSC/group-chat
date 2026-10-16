// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IERC20Payment {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}
