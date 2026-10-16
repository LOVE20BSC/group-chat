// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20Stake} from "../interfaces/external/ILOVE20Stake.sol";
import {IBaseTokenScopeManager} from "../interfaces/managers/IBaseTokenScopeManager.sol";
import {BaseTokenManager} from "./BaseTokenManager.sol";

abstract contract BaseTokenScopeManager is BaseTokenManager, IBaseTokenScopeManager {
    mapping(uint256 => address) public tokenOfGroup;
    mapping(address => uint256) public groupIdOfToken;
    address[] internal _tokens;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address extensionCenter_
    ) BaseTokenManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, extensionCenter_) {}

    function tokensCount() external view returns (uint256) {
        return _tokens.length;
    }

    function tokens(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (address[] memory tokenList, uint256[] memory groupIds)
    {
        uint256 count = _pageCount(_tokens.length, offset, limit);
        tokenList = new address[](count);
        groupIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            address token = _tokens[_pageIndex(_tokens.length, offset, i, reverse)];
            tokenList[i] = token;
            groupIds[i] = groupIdOfToken[token];
        }
    }

    function voteWeightOf(uint256 groupId, address voter) external view returns (uint256) {
        address token = tokenOfGroup[groupId];
        if (token == address(0)) {
            return 0;
        }
        return _tokenGovVoteWeight(token, voter);
    }

    function totalVoteWeight(uint256 groupId) external view returns (uint256) {
        address token = tokenOfGroup[groupId];
        if (token == address(0)) {
            return 0;
        }
        return ILOVE20Stake(STAKE_ADDRESS).govVotesNum(token);
    }

    function _activateToken(address token, string memory managerPrefix) internal returns (uint256 groupId) {
        _requireLOVE20Token(token);
        _requireNotManaged(groupIdOfToken[token] != 0);

        groupId = _mintManagedGroup(_tokenGroupNameStem(managerPrefix, token));
        tokenOfGroup[groupId] = token;
        groupIdOfToken[token] = groupId;
        _tokens.push(token);
        _activateManagedGroup(groupId);
        emit Activate(token, groupId, msg.sender);
    }
}
