// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseTokenScopeManager} from "./BaseTokenScopeManager.sol";

contract TokenGovManager is BaseTokenScopeManager {
    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address extensionCenter_
    ) BaseTokenScopeManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, extensionCenter_) {}

    function activate(address token) external returns (uint256 groupId) {
        return _activateToken(token, "mgr_token_gov_");
    }

    function canPost(uint256 groupId, uint256, address senderAddress) external view returns (bool) {
        address token = tokenOfGroup[groupId];
        return token != address(0) && _tokenGovVoteWeight(token, senderAddress) != 0;
    }
}
