// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IBaseManager} from "./IBaseManager.sol";

interface IBaseTokenActionScopeManager is IBaseManager {
    event Activate(address indexed token, uint256 indexed actionId, uint256 indexed groupId, address operator);

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
