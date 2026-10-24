// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {BaseTokenScopeManager} from "./BaseTokenScopeManager.sol";

contract TokenGovManager is BaseTokenScopeManager {
    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_
    ) BaseTokenScopeManager(
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
        address token = _tokenOfGroup[groupId];
        return token != address(0) && _tokenGovVoteWeight(token, senderId) != 0;
    }
}
