// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {BaseTokenActionScopeManager} from "./BaseTokenActionScopeManager.sol";

contract TokenActionGovManager is BaseTokenActionScopeManager {
    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_,
        uint256 recentRounds_
    )
        BaseTokenActionScopeManager(
            groupChat_,
            banSource_,
            beforePostPlugin_,
            afterPostPlugin_,
            actionTarget_,
            recentRounds_
        )
    {}

    function activate(address token, uint256 actionId) external returns (uint256 groupId) {
        return _activateManagedAction(token, actionId, "mgr_action_gov_");
    }

    function canPost(uint256 groupId, uint256 senderId) external view returns (bool) {
        ManagedAction storage action = _actionOfGroup[groupId];
        address token = action.token;
        return token != address(0) && _hasRecentActionVote(token, action.actionId, senderId);
    }
}
