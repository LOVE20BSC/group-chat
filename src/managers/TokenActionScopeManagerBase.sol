// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {TokenManagerBase} from "./TokenManagerBase.sol";
import {ITokenActionScopeManagerBase} from "../interfaces/managers/ITokenActionScopeManagerBase.sol";
import {IActionTarget} from "@action/interfaces/IActionTarget.sol";
import {ISubmit} from "@core/interfaces/ISubmit.sol";
import {IStake} from "@core/interfaces/IStake.sol";
import {IVote} from "@core/interfaces/IVote.sol";
import {Pagination} from "@libs/Pagination.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract TokenActionScopeManagerBase is TokenManagerBase, ITokenActionScopeManagerBase {
    uint256 public immutable RECENT_ROUNDS;
    address internal immutable SUBMIT_ADDRESS;

    struct ManagedAction {
        address tokenAddress;
        uint256 actionId;
    }

    // groupId => managed action
    mapping(uint256 => ManagedAction) internal _managedActionByGroupId;
    // tokenAddress => actionId => groupId; 0 means not managed
    mapping(address => mapping(uint256 => uint256)) internal _groupIdByActionId;
    // tokenAddress => managed actionIds, in activation order
    mapping(address => uint256[]) internal _actionIdsByTokenAddress;

    function actionByGroupId(uint256 groupId) external view returns (address tokenAddress, uint256 actionId) {
        ManagedAction storage action = _managedActionByGroupId[groupId];
        return (action.tokenAddress, action.actionId);
    }

    function groupIdByActionId(address tokenAddress, uint256 actionId) external view returns (uint256) {
        return _groupIdByActionId[tokenAddress][actionId];
    }

    constructor(
        address groupChatAddress,
        address banSourceAddress,
        address beforePostPluginAddress,
        address afterPostPluginAddress,
        address actionTargetAddress,
        uint256 recentRounds
    ) TokenManagerBase(
        groupChatAddress,
        banSourceAddress,
        beforePostPluginAddress,
        afterPostPluginAddress,
        actionTargetAddress
    ) {
        SUBMIT_ADDRESS = IActionTarget(ACTION_TARGET_ADDRESS).SUBMIT_ADDRESS();
        RECENT_ROUNDS = recentRounds;
    }

    function actions(address tokenAddress, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory actionIds, uint256[] memory groupIds, uint256 totalCount)
    {
        uint256[] storage source = _actionIdsByTokenAddress[tokenAddress];
        totalCount = source.length;
        uint256 count = Pagination.pageCount(totalCount, offset, limit);
        actionIds = new uint256[](count);
        groupIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 actionId = source[Pagination.pageIndex(totalCount, offset, i, reverse)];
            actionIds[i] = actionId;
            groupIds[i] = _groupIdByActionId[tokenAddress][actionId];
        }
    }

    function groupIdsByActionIds(address tokenAddress, uint256[] calldata actionIds)
        external
        view
        returns (uint256[] memory groupIds)
    {
        groupIds = new uint256[](actionIds.length);
        for (uint256 i = 0; i < actionIds.length; i++) {
            groupIds[i] = _groupIdByActionId[tokenAddress][actionIds[i]];
        }
    }

    function actionsByGroupIds(uint256[] calldata groupIds)
        external
        view
        returns (address[] memory tokens, uint256[] memory actionIds)
    {
        tokens = new address[](groupIds.length);
        actionIds = new uint256[](groupIds.length);
        for (uint256 i = 0; i < groupIds.length; i++) {
            ManagedAction storage action = _managedActionByGroupId[groupIds[i]];
            tokens[i] = action.tokenAddress;
            actionIds[i] = action.actionId;
        }
    }

    function voteWeight(uint256 groupId, uint256 voterId) external view returns (uint256) {
        ManagedAction storage action = _managedActionByGroupId[groupId];
        address tokenAddress = action.tokenAddress;
        if (tokenAddress == address(0)) {
            return 0;
        }
        return _currentActionVoteWeight(tokenAddress, action.actionId, voterId);
    }

    function totalVoteWeight(uint256 groupId) external view returns (uint256) {
        ManagedAction storage action = _managedActionByGroupId[groupId];
        address tokenAddress = action.tokenAddress;
        if (tokenAddress == address(0)) {
            return 0;
        }
        return IStake(STAKE_ADDRESS).totalValidGovVotes(tokenAddress, currentPhase());
    }

    function _activateManagedAction(address tokenAddress, uint256 actionId) internal returns (uint256 groupId) {
        _requireLOVE20Token(tokenAddress);
        _requireExistingAction(tokenAddress, actionId);
        _requireNotManaged(_groupIdByActionId[tokenAddress][actionId]);

        bool requiresTestPrefix = _love20TokenRequiresTestPrefix();
        string memory symbol = _tokenNamePayload(tokenAddress);
        string memory action = Strings.toString(actionId);
        string memory payload = bytes(symbol).length == 0 ? action : string(abi.encodePacked(symbol, "_", action));
        (string memory stem, uint256 randomHexLength) = _managedGroupNameStem(payload, requiresTestPrefix);
        groupId = _mintManagedGroup(stem, randomHexLength, requiresTestPrefix);
        // forge-lint: disable-next-item(missing-events-access-control)
        _managedActionByGroupId[groupId] = ManagedAction({tokenAddress: tokenAddress, actionId: actionId});
        // forge-lint: disable-next-item(missing-events-access-control)
        _groupIdByActionId[tokenAddress][actionId] = groupId;
        _actionIdsByTokenAddress[tokenAddress].push(actionId);
        _activateManagedGroup(groupId);
        emit TokenActionGroupActivated({
            tokenAddress: tokenAddress,
            actionId: actionId,
            groupId: groupId,
            operator: msg.sender
        });
    }

    function _requireExistingAction(address tokenAddress, uint256 actionId) internal view {
        (, uint256 proposalCount) = ISubmit(SUBMIT_ADDRESS).proposalIds(tokenAddress, 0, 0, false);
        if (actionId == 0 || actionId > proposalCount) {
            revert ActionNotExist(tokenAddress, actionId);
        }
    }

    function _hasRecentActionVote(address tokenAddress, uint256 actionId, uint256 memberId)
        internal
        view
        returns (bool)
    {
        uint256 round = IVote(VOTE_ADDRESS).currentRound();
        for (uint256 i = 0; i < RECENT_ROUNDS; i++) {
            if (IVote(VOTE_ADDRESS).voteAmountByMemberIdByProposalId(tokenAddress, round, memberId, actionId) != 0) {
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

    function _currentActionVoteWeight(address tokenAddress, uint256 actionId, uint256 memberId)
        internal
        view
        returns (uint256)
    {
        return IVote(VOTE_ADDRESS).voteAmountByMemberIdByProposalId(
            tokenAddress, IVote(VOTE_ADDRESS).currentRound(), memberId, actionId
        );
    }
}
