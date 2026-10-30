// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IManagerBase} from "./IManagerBase.sol";

interface ITokenScopeManagerBaseEvents {
    event TokenGroupActivated(
        address indexed tokenAddress,
        uint256 indexed groupId,
        address indexed operator
    );
}

interface ITokenScopeManagerBase is IManagerBase, ITokenScopeManagerBaseEvents {
    function activate(address tokenAddress) external returns (uint256 groupId);

    function tokenAddressByGroupId(uint256 groupId) external view returns (address);

    function groupIdByTokenAddress(address tokenAddress) external view returns (uint256);

    function tokens(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (address[] memory tokenList, uint256[] memory groupIds, uint256 totalCount);
}
