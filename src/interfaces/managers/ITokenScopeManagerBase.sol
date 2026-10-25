// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IManagerBase} from "./IManagerBase.sol";

interface ITokenScopeManagerBase is IManagerBase {
    event Activate(address indexed token, uint256 indexed groupId, address indexed operator);

    function activate(address token) external returns (uint256 groupId);

    function tokenOfGroup(uint256 groupId) external view returns (address);

    function groupIdOfToken(address token) external view returns (uint256);

    function tokensCount() external view returns (uint256);

    function tokens(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (address[] memory tokenList, uint256[] memory groupIds);
}
