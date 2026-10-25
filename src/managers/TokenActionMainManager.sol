// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IActionTarget} from "@action/interfaces/IActionTarget.sol";
import {TokenActionScopeManagerBase} from "./TokenActionScopeManagerBase.sol";

contract TokenActionMainManager is TokenActionScopeManagerBase {
    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_,
        uint256 recentRounds_
    )
        TokenActionScopeManagerBase(
            groupChat_,
            banSource_,
            beforePostPlugin_,
            afterPostPlugin_,
            actionTarget_,
            recentRounds_
        )
    {}

    function _typeCode() internal pure override returns (string memory) {
        return "am";
    }

    function activate(address token, uint256 actionId) external returns (uint256 groupId) {
        return _activateManagedAction(token, actionId);
    }

    function canPost(uint256 groupId, uint256 senderId) external view returns (bool) {
        ManagedAction storage action = _actionOfGroup[groupId];
        address token = action.token;
        return token != address(0)
            && (
                _hasRecentActionVote(token, action.actionId, senderId)
                    || _hasActionParticipation(token, action.actionId, senderId)
            );
    }

    function _hasActionParticipation(address token, uint256 actionId, uint256 memberId)
        internal
        view
        returns (bool)
    {
        return IActionTarget(ACTION_TARGET_ADDRESS).isJoined(token, actionId, memberId);
    }
}
