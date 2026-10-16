// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseTokenActionScopeManager} from "./BaseTokenActionScopeManager.sol";

contract TokenActionGovManager is BaseTokenActionScopeManager {
    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address extensionCenter_,
        uint256 recentRounds_
    )
        BaseTokenActionScopeManager(
            groupChat_,
            banSource_,
            beforePostPlugin_,
            afterPostPlugin_,
            extensionCenter_,
            recentRounds_
        )
    {}

    function activate(address token, uint256 actionId) external returns (uint256 groupId) {
        return _activateManagedAction(token, actionId, "mgr_action_gov_");
    }

    function canPost(uint256 groupId, uint256, address senderAddress) external view returns (bool) {
        ManagedAction storage action = actionOfGroup[groupId];
        address token = action.token;
        return token != address(0) && _hasRecentActionVote(token, action.actionId, senderAddress);
    }
}
