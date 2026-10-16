// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC20Balance} from "../interfaces/external/IERC20Balance.sol";
import {IExtensionCenter} from "../interfaces/external/IExtensionCenter.sol";
import {ILOVE20Join} from "../interfaces/external/ILOVE20Join.sol";
import {BaseTokenScopeManager} from "./BaseTokenScopeManager.sol";

contract TokenMainManager is BaseTokenScopeManager {
    address internal immutable JOIN_ADDRESS;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address extensionCenter_
    ) BaseTokenScopeManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, extensionCenter_) {
        address join = IExtensionCenter(extensionCenter_).joinAddress();
        _requireCode(join);

        JOIN_ADDRESS = join;
    }

    function activate(address token) external returns (uint256 groupId) {
        return _activateToken(token, "mgr_token_main_");
    }

    function canPost(uint256 groupId, uint256, address senderAddress) external view returns (bool) {
        address token = tokenOfGroup[groupId];
        return token != address(0)
            && (
                _hasTokenBalance(token, senderAddress) || _tokenGovVoteWeight(token, senderAddress) != 0
                    || _hasTokenActionParticipation(token, senderAddress)
            );
    }

    function _hasTokenBalance(address token, address account) internal view returns (bool) {
        return IERC20Balance(token).balanceOf(account) > 1;
    }

    function _hasTokenActionParticipation(address token, address account) internal view returns (bool) {
        return ILOVE20Join(JOIN_ADDRESS).amountByAccount(token, account) != 0;
    }
}
