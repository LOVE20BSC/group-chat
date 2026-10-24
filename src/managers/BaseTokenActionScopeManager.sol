// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {BaseTokenManager} from "./BaseTokenManager.sol";
import {IBaseTokenActionScopeManager} from "../interfaces/managers/IBaseTokenActionScopeManager.sol";
import {ISubmit} from "@core/interfaces/ISubmit.sol";
import {IStake} from "@core/interfaces/IStake.sol";
import {IVote} from "@core/interfaces/IVote.sol";
import {Pagination} from "@libs/Pagination.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract BaseTokenActionScopeManager is BaseTokenManager, IBaseTokenActionScopeManager {
    uint256 public immutable RECENT_ROUNDS;

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external
        view
        returns (bytes4)
    {
        return _onERC721ReceivedFromMint(operator, from, tokenId);
    }

    struct ManagedAction {
        address token;
        uint256 actionId;
    }

    mapping(uint256 => ManagedAction) internal _actionOfGroup;
    mapping(address => mapping(uint256 => uint256)) internal _groupIdOfAction;
    mapping(address => uint256[]) internal _actionIdsByToken;

    function actionOfGroup(uint256 groupId) external view returns (address token, uint256 actionId) {
        ManagedAction storage action = _actionOfGroup[groupId];
        return (action.token, action.actionId);
    }

    function groupIdOfAction(address token, uint256 actionId) external view returns (uint256) {
        return _groupIdOfAction[token][actionId];
    }

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_,
        uint256 recentRounds_
    ) BaseTokenManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, actionTarget_) {
        RECENT_ROUNDS = recentRounds_;
    }

    function actionsByTokenCount(address token) external view returns (uint256) {
        return _actionIdsByToken[token].length;
    }

    function actionsByToken(address token, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory actionIds, uint256[] memory groupIds)
    {
        uint256[] storage source = _actionIdsByToken[token];
        uint256 count = Pagination.pageCount(source.length, offset, limit);
        actionIds = new uint256[](count);
        groupIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 actionId = source[Pagination.pageIndex(source.length, offset, i, reverse)];
            actionIds[i] = actionId;
            groupIds[i] = _groupIdOfAction[token][actionId];
        }
    }

    function groupIdsOfActions(address token, uint256[] calldata actionIds)
        external
        view
        returns (uint256[] memory groupIds)
    {
        groupIds = new uint256[](actionIds.length);
        for (uint256 i = 0; i < actionIds.length; i++) {
            groupIds[i] = _groupIdOfAction[token][actionIds[i]];
        }
    }

    function actionsOfGroups(uint256[] calldata groupIds)
        external
        view
        returns (address[] memory tokens, uint256[] memory actionIds)
    {
        tokens = new address[](groupIds.length);
        actionIds = new uint256[](groupIds.length);
        for (uint256 i = 0; i < groupIds.length; i++) {
            ManagedAction storage action = _actionOfGroup[groupIds[i]];
            tokens[i] = action.token;
            actionIds[i] = action.actionId;
        }
    }

    function voteWeightOf(uint256 groupId, uint256 voterId) external view returns (uint256) {
        ManagedAction storage action = _actionOfGroup[groupId];
        address token = action.token;
        if (token == address(0)) {
            return 0;
        }
        return _currentActionVoteWeight(token, action.actionId, voterId);
    }

    function totalVoteWeight(uint256 groupId) external view returns (uint256) {
        ManagedAction storage action = _actionOfGroup[groupId];
        address token = action.token;
        if (token == address(0)) {
            return 0;
        }
        return IStake(STAKE_ADDRESS).globalGovVotes(token);
    }

    function _activateManagedAction(address token, uint256 actionId) internal returns (uint256 groupId) {
        _requireLOVE20Token(token);
        _requireExistingAction(token, actionId);
        _requireNotManaged(_groupIdOfAction[token][actionId]);

        bool requiresTestPrefix = _love20TokenRequiresTestPrefix();
        string memory symbol = _tokenNamePayload(token);
        string memory action = Strings.toString(actionId);
        string memory payload = bytes(symbol).length == 0 ? action : string(abi.encodePacked(symbol, "_", action));
        (string memory stem, uint256 randomHexLength) = _managedGroupNameStem(payload, requiresTestPrefix);
        groupId = _mintManagedGroup(stem, randomHexLength, requiresTestPrefix);
        // forge-lint: disable-next-item(missing-events-access-control)
        _actionOfGroup[groupId] = ManagedAction({token: token, actionId: actionId});
        // forge-lint: disable-next-item(missing-events-access-control)
        _groupIdOfAction[token][actionId] = groupId;
        _actionIdsByToken[token].push(actionId);
        _activateManagedGroup(groupId);
        emit Activate(token, actionId, groupId, msg.sender);
    }

    function _requireExistingAction(address token, uint256 actionId) internal view {
        (, uint256 proposalCount) = ISubmit(SUBMIT_ADDRESS).proposalIds(token, 0, 0, false);
        if (actionId == 0 || actionId > proposalCount) {
            revert ActionNotExist(token, actionId);
        }
    }

    function _hasRecentActionVote(address token, uint256 actionId, uint256 memberId) internal view returns (bool) {
        uint256 round = IVote(VOTE_ADDRESS).currentRound();
        for (uint256 i = 0; i < RECENT_ROUNDS; i++) {
            if (IVote(VOTE_ADDRESS).votesNumByMemberIdByProposalId(token, round, memberId, actionId) != 0) {
                return true;
            }
            if (round <= 1) {
                break;
            }
            unchecked {
                round--;
            }
        }
        return false;
    }

    function _currentActionVoteWeight(address token, uint256 actionId, uint256 memberId)
        internal
        view
        returns (uint256)
    {
        return IVote(VOTE_ADDRESS).votesNumByMemberIdByProposalId(
            token, IVote(VOTE_ADDRESS).currentRound(), memberId, actionId
        );
    }
}
