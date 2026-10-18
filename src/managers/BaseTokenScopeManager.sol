// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {BaseTokenManager} from "./BaseTokenManager.sol";
import {IBaseTokenScopeManager} from "../interfaces/managers/IBaseTokenScopeManager.sol";
import {IStake} from "core/src/interfaces/IStake.sol";

abstract contract BaseTokenScopeManager is BaseTokenManager, IBaseTokenScopeManager {
    function onERC721Received(address, address from, uint256, bytes calldata) external view returns (bytes4) {
        return _onERC721ReceivedFromMint(from);
    }

    mapping(uint256 => address) public tokenOfGroup;
    mapping(address => uint256) public groupIdOfToken;
    address[] internal _tokens;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_
    ) BaseTokenManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, actionTarget_) {}

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

    function voteWeightOf(uint256 groupId, uint256 voterId) external view returns (uint256) {
        address token = tokenOfGroup[groupId];
        if (token == address(0)) {
            return 0;
        }
        return _tokenGovVoteWeight(token, voterId);
    }

    function totalVoteWeight(uint256 groupId) external view returns (uint256) {
        address token = tokenOfGroup[groupId];
        if (token == address(0)) {
            return 0;
        }
        return IStake(STAKE_ADDRESS).globalGovVotes(token);
    }

    function _activateToken(address token, string memory managerPrefix) internal returns (uint256 groupId) {
        _requireLOVE20Token(token);
        _requireNotManaged(groupIdOfToken[token] != 0);

        groupId = _mintManagedGroup(_tokenGroupNameStem(managerPrefix, token));
        // forge-lint: disable-next-item(missing-events-access-control)
        tokenOfGroup[groupId] = token;
        // forge-lint: disable-next-item(missing-events-access-control)
        groupIdOfToken[token] = groupId;
        _tokens.push(token);
        _activateManagedGroup(groupId);
        emit Activate(token, groupId, msg.sender);
    }
}
