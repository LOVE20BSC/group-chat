// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {TokenScopeManagerBase} from "./TokenScopeManagerBase.sol";

contract TokenGovManager is TokenScopeManagerBase {
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
        return "tg";
    }

    function activate(address tokenAddress) external returns (uint256 groupId) {
        return _activateToken(tokenAddress);
    }

    function isSenderAllowed(uint256 groupId, uint256 senderId) external view returns (bool) {
        return voteWeight(groupId, senderId) != 0;
    }
}
