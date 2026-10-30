// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IActionTarget} from "@action/interfaces/IActionTarget.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MemberOwner} from "@action/MemberOwner.sol";
import {TokenScopeManagerBase} from "./TokenScopeManagerBase.sol";

contract TokenMainManager is TokenScopeManagerBase {
    constructor(
        address groupChatAddress,
        address banSourceAddress,
        address beforePostPluginAddress,
        address afterPostPluginAddress,
        address actionTargetAddress
    ) TokenScopeManagerBase(
        groupChatAddress,
        banSourceAddress,
        beforePostPluginAddress,
        afterPostPluginAddress,
        actionTargetAddress
    ) {}

    function _typeCode() internal pure override returns (string memory) {
        return "tm";
    }

    function activate(address tokenAddress) external returns (uint256 groupId) {
        return _activateToken(tokenAddress);
    }

    function isSenderAllowed(uint256 groupId, uint256 senderId) external view returns (bool) {
        address tokenAddress = _tokenAddressByGroupId[groupId];
        return tokenAddress != address(0)
            && (
                _hasTokenBalance(tokenAddress, senderId) || _voteWeight(tokenAddress, senderId) != 0
                    || _hasTokenActionParticipation(tokenAddress, senderId)
            );
    }

    function _hasTokenBalance(address tokenAddress, uint256 memberId) internal view returns (bool) {
        return IERC20(tokenAddress).balanceOf(MemberOwner.ownerOrZero(GROUP_ADDRESS, memberId)) > 0;
    }

    function _hasTokenActionParticipation(address tokenAddress, uint256 memberId) internal view returns (bool) {
        (, uint256 joinedActionTotal) =
            IActionTarget(ACTION_TARGET_ADDRESS).actionIdsByMemberId(tokenAddress, memberId, 0, 1, false);
        return joinedActionTotal != 0;
    }
}
