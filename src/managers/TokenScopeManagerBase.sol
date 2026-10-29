// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {TokenManagerBase} from "./TokenManagerBase.sol";
import {ITokenScopeManagerBase} from "../interfaces/managers/ITokenScopeManagerBase.sol";
import {IStake} from "@core/interfaces/IStake.sol";
import {Pagination} from "@libs/Pagination.sol";

abstract contract TokenScopeManagerBase is TokenManagerBase, ITokenScopeManagerBase {
    mapping(uint256 => address) internal _tokenOfGroup;
    mapping(address => uint256) internal _groupIdOfToken;
    address[] internal _tokens;

    function tokenOfGroup(uint256 groupId) external view returns (address) {
        return _tokenOfGroup[groupId];
    }

    function groupIdOfToken(address token) external view returns (uint256) {
        return _groupIdOfToken[token];
    }

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_
    ) TokenManagerBase(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, actionTarget_) {}

    function tokensCount() external view returns (uint256) {
        return _tokens.length;
    }

    function tokens(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (address[] memory tokenList, uint256[] memory groupIds)
    {
        uint256 count = Pagination.pageCount(_tokens.length, offset, limit);
        tokenList = new address[](count);
        groupIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            address token = _tokens[Pagination.pageIndex(_tokens.length, offset, i, reverse)];
            tokenList[i] = token;
            groupIds[i] = _groupIdOfToken[token];
        }
    }

    function voteWeightOf(uint256 groupId, uint256 voterId) public view returns (uint256) {
        return _voteWeightOf(_tokenOfGroup[groupId], voterId);
    }

    function totalVoteWeight(uint256 groupId) external view returns (uint256) {
        address token = _tokenOfGroup[groupId];
        if (token == address(0)) {
            return 0;
        }
        return IStake(STAKE_ADDRESS).totalValidGovVotes(token, currentPhase());
    }

    function _voteWeightOf(address token, uint256 voterId) internal view returns (uint256) {
        if (token == address(0)) {
            return 0;
        }
        return IStake(STAKE_ADDRESS).validGovVotes(token, currentPhase(), voterId);
    }

    function _activateToken(address token) internal returns (uint256 groupId) {
        _requireLOVE20Token(token);
        _requireNotManaged(_groupIdOfToken[token]);

        bool requiresTestPrefix = _love20TokenRequiresTestPrefix();
        (string memory stem, uint256 randomHexLength) =
            _managedGroupNameStem(_tokenNamePayload(token), requiresTestPrefix);
        groupId = _mintManagedGroup(stem, randomHexLength, requiresTestPrefix);
        // forge-lint: disable-next-item(missing-events-access-control)
        _tokenOfGroup[groupId] = token;
        // forge-lint: disable-next-item(missing-events-access-control)
        _groupIdOfToken[token] = groupId;
        _tokens.push(token);
        _activateManagedGroup(groupId);
        emit TokenGroupActivated({
            tokenAddress: token,
            groupId: groupId,
            operator: msg.sender
        });
    }
}
