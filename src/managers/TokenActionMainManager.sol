// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IExtensionCenter} from "../interfaces/external/IExtensionCenter.sol";
import {ILOVE20Join} from "../interfaces/external/ILOVE20Join.sol";
import {BaseTokenActionScopeManager} from "./BaseTokenActionScopeManager.sol";

contract TokenActionMainManager is BaseTokenActionScopeManager {
    address internal immutable JOIN_ADDRESS;

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
    {
        address join = IExtensionCenter(extensionCenter_).joinAddress();
        _requireCode(join);

        JOIN_ADDRESS = join;
    }

    function activate(address token, uint256 actionId) external returns (uint256 groupId) {
        return _activateManagedAction(token, actionId, "mgr_action_main_");
    }

    function canPost(uint256 groupId, uint256, address senderAddress) external view returns (bool) {
        ManagedAction storage action = actionOfGroup[groupId];
        address token = action.token;
        return token != address(0)
            && (
                _hasRecentActionVote(token, action.actionId, senderAddress)
                    || _hasActionParticipation(token, action.actionId, senderAddress)
            );
    }

    function _hasActionParticipation(address token, uint256 actionId, address account) internal view returns (bool) {
        return ILOVE20Join(JOIN_ADDRESS).amountByActionIdByAccount(token, actionId, account) != 0
            || IExtensionCenter(EXTENSION_CENTER_ADDRESS).isAccountJoined(token, actionId, account);
    }
}
