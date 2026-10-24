// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {BaseTokenManager} from "./BaseTokenManager.sol";
import {IBaseTokenScopeManager} from "../interfaces/managers/IBaseTokenScopeManager.sol";
import {IStake} from "@core/interfaces/IStake.sol";
import {Pagination} from "@libs/Pagination.sol";

abstract contract BaseTokenScopeManager is BaseTokenManager, IBaseTokenScopeManager {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external
        view
        returns (bytes4)
    {
        return _onERC721ReceivedFromMint(operator, from, tokenId);
    }

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
    ) BaseTokenManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, actionTarget_) {}

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

    function voteWeightOf(uint256 groupId, uint256 voterId) external view returns (uint256) {
        address token = _tokenOfGroup[groupId];
        if (token == address(0)) {
            return 0;
        }
        return _tokenGovVoteWeight(token, voterId);
    }

    function totalVoteWeight(uint256 groupId) external view returns (uint256) {
        address token = _tokenOfGroup[groupId];
        if (token == address(0)) {
            return 0;
        }
        return IStake(STAKE_ADDRESS).globalGovVotes(token);
    }

    function _activateToken(address token, string memory managerPrefix) internal returns (uint256 groupId) {
        _requireLOVE20Token(token);
        _requireNotManaged(_groupIdOfToken[token]);

        groupId = _mintManagedGroup(_tokenGroupNameStem(managerPrefix, token));
        // forge-lint: disable-next-item(missing-events-access-control)
        _tokenOfGroup[groupId] = token;
        // forge-lint: disable-next-item(missing-events-access-control)
        _groupIdOfToken[token] = groupId;
        _tokens.push(token);
        _activateManagedGroup(groupId);
        emit Activate(token, groupId, msg.sender);
    }
}
