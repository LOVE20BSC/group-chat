// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IActionTarget} from "@action/interfaces/IActionTarget.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MemberOwner} from "@action/MemberOwner.sol";
import {TokenScopeManagerBase} from "./TokenScopeManagerBase.sol";

contract TokenMainManager is TokenScopeManagerBase {
    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_
    ) TokenScopeManagerBase(
        groupChat_,
        banSource_,
        beforePostPlugin_,
        afterPostPlugin_,
        actionTarget_
    ) {}

    function _typeCode() internal pure override returns (string memory) {
        return "tm";
    }

    function activate(address token) external returns (uint256 groupId) {
        return _activateToken(token);
    }

    function canPost(uint256 groupId, uint256 senderId) external view returns (bool) {
        address token = _tokenOfGroup[groupId];
        return token != address(0)
            && (
                _hasTokenBalance(token, senderId) || _voteWeightOf(token, senderId) != 0
                    || _hasTokenActionParticipation(token, senderId)
            );
    }

    function _hasTokenBalance(address token, uint256 memberId) internal view returns (bool) {
        return IERC20(token).balanceOf(MemberOwner.ofOrZero(GROUP_ADDRESS, memberId)) > 0;
    }

    function _hasTokenActionParticipation(address token, uint256 memberId) internal view returns (bool) {
        (, uint256 joinedActionTotal) =
            IActionTarget(ACTION_TARGET_ADDRESS).actionIdsByMemberId(token, memberId, 0, 1, false);
        return joinedActionTotal != 0;
    }
}
