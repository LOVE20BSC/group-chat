// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {TokenManagerBase} from "./TokenManagerBase.sol";
import {ITokenScopeManagerBase} from "../interfaces/managers/ITokenScopeManagerBase.sol";
import {IStake} from "@core/interfaces/IStake.sol";
import {Pagination} from "@libs/Pagination.sol";

abstract contract TokenScopeManagerBase is TokenManagerBase, ITokenScopeManagerBase {
    // groupId => managed token address
    mapping(uint256 => address) internal _tokenAddressByGroupId;
    // tokenAddress => groupId; 0 means not managed
    mapping(address => uint256) internal _groupIdByTokenAddress;
    // managed token addresses, in activation order
    address[] internal _tokens;

    function tokenAddressByGroupId(uint256 groupId) external view returns (address) {
        return _tokenAddressByGroupId[groupId];
    }

    function groupIdByTokenAddress(address tokenAddress) external view returns (uint256) {
        return _groupIdByTokenAddress[tokenAddress];
    }

    constructor(
        address groupChatAddress,
        address banSourceAddress,
        address beforePostPluginAddress,
        address afterPostPluginAddress,
        address actionTargetAddress
    ) TokenManagerBase(
        groupChatAddress,
        banSourceAddress,
        beforePostPluginAddress,
        afterPostPluginAddress,
        actionTargetAddress
    ) {}

    function tokens(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (address[] memory tokenList, uint256[] memory groupIds, uint256 totalCount)
    {
        totalCount = _tokens.length;
        uint256 count = Pagination.pageCount(totalCount, offset, limit);
        tokenList = new address[](count);
        groupIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            address tokenAddress = _tokens[Pagination.pageIndex(totalCount, offset, i, reverse)];
            tokenList[i] = tokenAddress;
            groupIds[i] = _groupIdByTokenAddress[tokenAddress];
        }
    }

    function voteWeight(uint256 groupId, uint256 voterId) public view returns (uint256) {
        return _voteWeight(_tokenAddressByGroupId[groupId], voterId);
    }

    function totalVoteWeight(uint256 groupId) external view returns (uint256) {
        address tokenAddress = _tokenAddressByGroupId[groupId];
        if (tokenAddress == address(0)) {
            return 0;
        }
        return IStake(STAKE_ADDRESS).totalValidGovVotes(tokenAddress, currentPhase());
    }

    function _voteWeight(address tokenAddress, uint256 voterId) internal view returns (uint256) {
        if (tokenAddress == address(0)) {
            return 0;
        }
        return IStake(STAKE_ADDRESS).validGovVotes(tokenAddress, currentPhase(), voterId);
    }

    function _activateToken(address tokenAddress) internal returns (uint256 groupId) {
        _requireLOVE20Token(tokenAddress);
        _requireNotManaged(_groupIdByTokenAddress[tokenAddress]);

        bool requiresTestPrefix = _love20TokenRequiresTestPrefix();
        (string memory stem, uint256 randomHexLength) =
            _managedGroupNameStem(_tokenNamePayload(tokenAddress), requiresTestPrefix);
        groupId = _mintManagedGroup(stem, randomHexLength, requiresTestPrefix);
        // forge-lint: disable-next-item(missing-events-access-control)
        _tokenAddressByGroupId[groupId] = tokenAddress;
        // forge-lint: disable-next-item(missing-events-access-control)
        _groupIdByTokenAddress[tokenAddress] = groupId;
        _tokens.push(tokenAddress);
        _activateManagedGroup(groupId);
        emit TokenGroupActivated({
            tokenAddress: tokenAddress,
            groupId: groupId,
            operator: msg.sender
        });
    }
}
