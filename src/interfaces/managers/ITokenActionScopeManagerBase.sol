// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IManagerBase} from "./IManagerBase.sol";

interface ITokenActionScopeManagerBaseErrors {
    error ActionNotExist(address tokenAddress, uint256 actionId);
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

    function activate(address token, uint256 actionId) external returns (uint256 groupId);

    function actionOfGroup(uint256 groupId) external view returns (address token, uint256 actionId);

    function groupIdOfAction(address token, uint256 actionId) external view returns (uint256);

    function groupIdsOfActions(address token, uint256[] calldata actionIds)
        external
        view
        returns (uint256[] memory groupIds);

    function actionsOfGroups(uint256[] calldata groupIds)
        external
        view
        returns (address[] memory tokens, uint256[] memory actionIds);

    function actionsByTokenCount(address token) external view returns (uint256);

    function actionsByToken(address token, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory actionIds, uint256[] memory groupIds);
}
