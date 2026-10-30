// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IManagerBase} from "./IManagerBase.sol";

interface ITokenActionScopeManagerBaseErrors {
    error ActionNotExist(
        address tokenAddress,
        uint256 actionId
    );
}

interface ITokenActionScopeManagerBaseEvents {
    event TokenActionGroupActivated(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address operator
    );
}

interface ITokenActionScopeManagerBase is
    IManagerBase,
    ITokenActionScopeManagerBaseEvents,
    ITokenActionScopeManagerBaseErrors
{
    function RECENT_ROUNDS() external view returns (uint256);

    function activate(address tokenAddress, uint256 actionId) external returns (uint256 groupId);

    function actionByGroupId(uint256 groupId) external view returns (address tokenAddress, uint256 actionId);

    function groupIdByActionId(address tokenAddress, uint256 actionId) external view returns (uint256);

    function groupIdsByActionIds(address tokenAddress, uint256[] calldata actionIds)
        external
        view
        returns (uint256[] memory groupIds);

    function actionsByGroupIds(uint256[] calldata groupIds)
        external
        view
        returns (address[] memory tokens, uint256[] memory actionIds);

    function actions(address tokenAddress, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory actionIds, uint256[] memory groupIds, uint256 totalCount);
}
