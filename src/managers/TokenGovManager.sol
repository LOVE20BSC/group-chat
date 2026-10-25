// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {TokenScopeManagerBase} from "./TokenScopeManagerBase.sol";

contract TokenGovManager is TokenScopeManagerBase {
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
        return "tg";
    }

    function activate(address token) external returns (uint256 groupId) {
        return _activateToken(token);
    }

    function canPost(uint256 groupId, uint256 senderId) external view returns (bool) {
        return voteWeightOf(groupId, senderId) != 0;
    }
}
