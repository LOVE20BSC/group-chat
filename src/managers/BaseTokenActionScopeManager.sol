// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IExtensionCenter} from "../interfaces/external/IExtensionCenter.sol";

import {ILOVE20Stake} from "../interfaces/external/ILOVE20Stake.sol";
import {ILOVE20Submit} from "../interfaces/external/ILOVE20Submit.sol";
import {ILOVE20Vote} from "../interfaces/external/ILOVE20Vote.sol";
import {IBaseTokenActionScopeManager} from "../interfaces/managers/IBaseTokenActionScopeManager.sol";
import {BaseTokenManager} from "./BaseTokenManager.sol";

abstract contract BaseTokenActionScopeManager is BaseTokenManager, IBaseTokenActionScopeManager {
    struct ManagedAction {
        address token;
        uint256 actionId;
    }

    address internal immutable VOTE_ADDRESS;
    address internal immutable SUBMIT_ADDRESS;
    uint256 public immutable RECENT_ROUNDS;

    mapping(uint256 => ManagedAction) public actionOfGroup;
    mapping(address => mapping(uint256 => uint256)) public groupIdOfAction;
    mapping(address => uint256[]) internal _actionIdsByToken;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address extensionCenter_,
        uint256 recentRounds_
    ) BaseTokenManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, extensionCenter_) {
        _requireRecentRounds(recentRounds_);

        address vote = IExtensionCenter(extensionCenter_).voteAddress();
        address submit = IExtensionCenter(extensionCenter_).submitAddress();
        _requireCode(vote);
        _requireCode(submit);

        VOTE_ADDRESS = vote;
        SUBMIT_ADDRESS = submit;
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
        uint256 count = _pageCount(source.length, offset, limit);
        actionIds = new uint256[](count);
        groupIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 actionId = source[_pageIndex(source.length, offset, i, reverse)];
            actionIds[i] = actionId;
            groupIds[i] = groupIdOfAction[token][actionId];
        }
    }

    function groupIdsOfActions(address token, uint256[] calldata actionIds)
        external
        view
        returns (uint256[] memory groupIds)
    {
        groupIds = new uint256[](actionIds.length);
        for (uint256 i = 0; i < actionIds.length; i++) {
            groupIds[i] = groupIdOfAction[token][actionIds[i]];
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
            ManagedAction storage action = actionOfGroup[groupIds[i]];
            tokens[i] = action.token;
            actionIds[i] = action.actionId;
        }
    }

    function voteWeightOf(uint256 groupId, address voter) external view returns (uint256) {
        ManagedAction storage action = actionOfGroup[groupId];
        address token = action.token;
        if (token == address(0)) {
            return 0;
        }
        return _currentActionVoteWeight(token, action.actionId, voter);
    }

    function totalVoteWeight(uint256 groupId) external view returns (uint256) {
        ManagedAction storage action = actionOfGroup[groupId];
        address token = action.token;
        if (token == address(0)) {
            return 0;
        }
        return ILOVE20Stake(STAKE_ADDRESS).govVotesNum(token);
    }

    function _activateManagedAction(address token, uint256 actionId, string memory managerPrefix)
        internal
        returns (uint256 groupId)
    {
        _requireLOVE20Token(token);
        _requireExistingAction(token, actionId);
        _requireNotManaged(groupIdOfAction[token][actionId] != 0);

        groupId = _mintManagedGroup(_tokenActionGroupNameStem(managerPrefix, token, actionId));
        actionOfGroup[groupId] = ManagedAction({token: token, actionId: actionId});
        groupIdOfAction[token][actionId] = groupId;
        _actionIdsByToken[token].push(actionId);
        _activateManagedGroup(groupId);
        emit Activate(token, actionId, groupId, msg.sender);
    }

    function _requireExistingAction(address token, uint256 actionId) internal view {
        if (actionId >= ILOVE20Submit(SUBMIT_ADDRESS).actionsCount(token)) {
            revert ActionIdNotExist();
        }
    }

    function _hasRecentActionVote(address token, uint256 actionId, address account) internal view returns (bool) {
        uint256 round = ILOVE20Vote(VOTE_ADDRESS).currentRound();
        for (uint256 i = 0; i < RECENT_ROUNDS; i++) {
            if (ILOVE20Vote(VOTE_ADDRESS).votesNumByAccountByActionId(token, round, account, actionId) != 0) {
                return true;
            }
            if (round == 0) {
                break;
            }
            unchecked {
                round--;
            }
        }
        return false;
    }

    function _currentActionVoteWeight(address token, uint256 actionId, address account)
        internal
        view
        returns (uint256)
    {
        return ILOVE20Vote(VOTE_ADDRESS).votesNumByAccountByActionId(
            token, ILOVE20Vote(VOTE_ADDRESS).currentRound(), account, actionId
        );
    }
}
