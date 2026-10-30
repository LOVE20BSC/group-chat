// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IActionTarget} from "@action/interfaces/IActionTarget.sol";
import {TokenActionScopeManagerBase} from "./TokenActionScopeManagerBase.sol";

contract TokenActionMainManager is TokenActionScopeManagerBase {
    constructor(
        address groupChatAddress,
        address banSourceAddress,
        address beforePostPluginAddress,
        address afterPostPluginAddress,
        address actionTargetAddress,
        uint256 recentRounds
    )
        TokenActionScopeManagerBase(
            groupChatAddress,
            banSourceAddress,
            beforePostPluginAddress,
            afterPostPluginAddress,
            actionTargetAddress,
            recentRounds
        )
    {}

    function _typeCode() internal pure override returns (string memory) {
        return "am";
    }

    function activate(address tokenAddress, uint256 actionId) external returns (uint256 groupId) {
        return _activateManagedAction(tokenAddress, actionId);
    }

    function isSenderAllowed(uint256 groupId, uint256 senderId) external view returns (bool) {
        ManagedAction storage action = _managedActionByGroupId[groupId];
        address tokenAddress = action.tokenAddress;
        return tokenAddress != address(0)
            && (
                _hasRecentActionVote(tokenAddress, action.actionId, senderId)
                    || _hasActionParticipation(tokenAddress, action.actionId, senderId)
            );
    }

    function _hasActionParticipation(address tokenAddress, uint256 actionId, uint256 memberId)
        internal
        view
        returns (bool)
    {
        return IActionTarget(ACTION_TARGET_ADDRESS).isJoined(tokenAddress, actionId, memberId);
    }
}
