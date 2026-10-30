// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IBanVoteWeightSource} from "../../interfaces/sources/ban/IBanVoteWeightSource.sol";
import {IGovVotedBanSource} from "../../interfaces/sources/ban/IGovVotedBanSource.sol";
import {MemberOwner} from "@action/MemberOwner.sol";
import {IMemberNFT} from "@core/interfaces/IMemberNFT.sol";
import {Uint256Set} from "@libs/Uint256Set.sol";

contract GovVotedBanSource is IGovVotedBanSource {
    using Uint256Set for Uint256Set.Storage;

    address public immutable GROUP_ADDRESS;
    uint256 public constant PRECISION = 1e18;
    uint256 public immutable MIN_SUPPORT_TO_OPPOSE_MULTIPLIER;
    uint256 public immutable BAN_THRESHOLD_RATIO;

    struct VoteState {
        bool supportBan;
        uint256 settledWeight;
    }

    struct TargetState {
        uint256 supportWeight;
        uint256 opposeWeight;
        Uint256Set.Storage voters;
        mapping(uint256 => VoteState) votes;
    }

    struct ChatState {
        Uint256Set.Storage senderIdTargets;
        mapping(uint256 => TargetState) senderIdTargetStates;
        Uint256Set.Storage senderIdBanList;
    }

    mapping(uint256 => ChatState) internal _states;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupAddress_, uint256 minSupportToOpposeMultiplier_, uint256 banThresholdRatio_) {
        GROUP_ADDRESS = groupAddress_;
        MIN_SUPPORT_TO_OPPOSE_MULTIPLIER = minSupportToOpposeMultiplier_;
        BAN_THRESHOLD_RATIO = banThresholdRatio_;
    }

    function voteBySenderId(uint256 groupId, uint256 targetSenderId, uint256 voterId, bool supportBan)
        external
        onlyVoterOwner(voterId)
    {
        _setSenderIdVote(groupId, targetSenderId, voterId, supportBan);
    }

    function clearVoteBySenderId(uint256 groupId, uint256 targetSenderId, uint256 voterId)
        external
        onlyVoterOwner(voterId)
    {
        _clearSenderIdVote(groupId, targetSenderId, voterId);
    }

    function refreshVoteBySenderId(uint256 groupId, uint256 targetSenderId, uint256 voterId) external {
        _refreshSenderIdVote(groupId, targetSenderId, voterId);
    }

    function voteWeightsBySenderIdsByVoter(uint256 groupId, uint256[] calldata senderIds, uint256 voterId)
        external
        view
        returns (uint256[] memory supportWeights, uint256[] memory opposeWeights)
    {
        supportWeights = new uint256[](senderIds.length);
        opposeWeights = new uint256[](senderIds.length);
        if (!_sourceHasCode(groupId)) {
            return (supportWeights, opposeWeights);
        }
        ChatState storage state = _states[groupId];
        for (uint256 i = 0; i < senderIds.length; i++) {
            VoteState storage vote = state.senderIdTargetStates[senderIds[i]].votes[voterId];
            (supportWeights[i], opposeWeights[i]) = _voteWeights(vote);
        }
    }

    function voteStatusBySenderId(uint256 groupId, uint256 senderId)
        external
        view
        returns (bool banned, uint256 supportWeight, uint256 opposeWeight)
    {
        if (!_sourceHasCode(groupId)) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, 0, 0);
        }
        ChatState storage state = _states[groupId];
        TargetState storage target = state.senderIdTargetStates[senderId];
        return (state.senderIdBanList.contains(senderId), target.supportWeight, target.opposeWeight);
    }

    function votedSenderIdsCount(uint256 groupId) external view returns (uint256) {
        if (!_sourceHasCode(groupId)) {
            return 0;
        }
        return _states[groupId].senderIdTargets.count();
    }

    function votedSenderIds(uint256 groupId, uint256 offset, uint256 limit)
        external
        view
        returns (
            uint256[] memory senderIds,
            uint256[] memory supportWeights,
            uint256[] memory opposeWeights,
            uint256[] memory voterCounts
        )
    {
        if (!_sourceHasCode(groupId)) {
            return (new uint256[](0), new uint256[](0), new uint256[](0), new uint256[](0));
        }

        ChatState storage state = _states[groupId];
        (senderIds,) = state.senderIdTargets.values(offset, limit, false);
        uint256 count = senderIds.length;
        supportWeights = new uint256[](count);
        opposeWeights = new uint256[](count);
        voterCounts = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 senderId = senderIds[i];
            TargetState storage target = state.senderIdTargetStates[senderId];
            supportWeights[i] = target.supportWeight;
            opposeWeights[i] = target.opposeWeight;
            voterCounts[i] = target.voters.count();
        }
    }

    function votersBySenderIdCount(uint256 groupId, uint256 senderId) external view returns (uint256) {
        if (!_sourceHasCode(groupId)) {
            return 0;
        }
        return _states[groupId].senderIdTargetStates[senderId].voters.count();
    }

    function votersBySenderId(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory voterIds, uint256[] memory supportWeights, uint256[] memory opposeWeights)
    {
        if (!_sourceHasCode(groupId)) {
            return (new uint256[](0), new uint256[](0), new uint256[](0));
        }
        return _votersPage(_states[groupId].senderIdTargetStates[senderId], offset, limit);
    }

    function isBanned(uint256 groupId, uint256 senderId) external view returns (bool) {
        return _states[groupId].senderIdBanList.contains(senderId);
    }

    function isSenderIdBannedBatch(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned)
    {
        Uint256Set.Storage storage banList = _states[groupId].senderIdBanList;
        banned = new bool[](senderIds.length);
        for (uint256 i = 0; i < senderIds.length; i++) {
            banned[i] = banList.contains(senderIds[i]);
        }
    }

    function voteStatusBySenderIds(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned, uint256[] memory supportWeights, uint256[] memory opposeWeights)
    {
        ChatState storage state = _states[groupId];
        banned = new bool[](senderIds.length);
        supportWeights = new uint256[](senderIds.length);
        opposeWeights = new uint256[](senderIds.length);
        for (uint256 i = 0; i < senderIds.length; i++) {
            uint256 senderId = senderIds[i];
            TargetState storage target = state.senderIdTargetStates[senderId];
            banned[i] = state.senderIdBanList.contains(senderId);
            supportWeights[i] = target.supportWeight;
            opposeWeights[i] = target.opposeWeight;
        }
    }

    modifier onlyVoterOwner(uint256 voterId) {
        if (IMemberNFT(GROUP_ADDRESS).ownerOf(voterId) != msg.sender) {
            revert NotMemberOwner(voterId);
        }
        _;
    }

    function _setSenderIdVote(uint256 groupId, uint256 targetSenderId, uint256 voterId, bool supportBan) internal {
        if (!_setVoteIfChanged(groupId, targetSenderId, voterId, supportBan)) {
            revert VoteUnchanged(groupId, targetSenderId, voterId);
        }
    }

    function _setVoteIfChanged(uint256 groupId, uint256 targetSenderId, uint256 voterId, bool supportBan)
        internal
        returns (bool changed)
    {
        _requireTarget(targetSenderId);
        address source = _sourceOrRevert(groupId);
        uint256 weight = _voteWeightOrRevert(source, groupId, voterId);
        if (weight == 0) {
            revert ZeroVoteWeight(groupId, voterId);
        }
        uint256 totalWeight = _totalVoteWeightOrRevert(source, groupId);

        ChatState storage state = _states[groupId];
        TargetState storage target = _targetState(state, targetSenderId);
        VoteState storage vote = target.votes[voterId];
        bool voteExists = vote.settledWeight != 0;
        if (voteExists && vote.supportBan == supportBan && vote.settledWeight == weight) {
            return false;
        }

        if (!voteExists) {
            state.senderIdTargets.add(targetSenderId);
            target.voters.add(voterId);
        } else {
            _removeWeight(target, vote.supportBan, vote.settledWeight);
        }

        _addWeight(target, supportBan, weight);
        vote.supportBan = supportBan;
        vote.settledWeight = weight;
        _settleVote(state, groupId, targetSenderId, voterId, supportBan, weight, totalWeight);
        return true;
    }

    function _clearSenderIdVote(uint256 groupId, uint256 targetSenderId, uint256 voterId) internal {
        if (!_clearVoteIfFound(groupId, targetSenderId, voterId)) {
            revert VoteNotFound(groupId, targetSenderId, voterId);
        }
    }

    function _clearVoteIfFound(uint256 groupId, uint256 targetSenderId, uint256 voterId) internal returns (bool found) {
        _requireTarget(targetSenderId);
        address source = _sourceOrRevert(groupId);
        uint256 totalWeight = _totalVoteWeightOrRevert(source, groupId);

        ChatState storage state = _states[groupId];
        TargetState storage target = _targetState(state, targetSenderId);
        VoteState storage vote = target.votes[voterId];
        if (vote.settledWeight == 0) {
            return false;
        }

        _removeVote(state, target, targetSenderId, voterId);
        _settleVote(state, groupId, targetSenderId, voterId, false, 0, totalWeight);
        return true;
    }

    function _refreshSenderIdVote(uint256 groupId, uint256 targetSenderId, uint256 voterId) internal {
        if (!_refreshVoteIfFound(groupId, targetSenderId, voterId)) {
            revert VoteNotFound(groupId, targetSenderId, voterId);
        }
    }

    function _refreshVoteIfFound(uint256 groupId, uint256 targetSenderId, uint256 voterId)
        internal
        returns (bool found)
    {
        _requireTarget(targetSenderId);
        address source = _sourceOrRevert(groupId);
        uint256 totalWeight = _totalVoteWeightOrRevert(source, groupId);

        ChatState storage state = _states[groupId];
        TargetState storage target = _targetState(state, targetSenderId);
        VoteState storage vote = target.votes[voterId];
        if (vote.settledWeight == 0) {
            return false;
        }

        uint256 weight = _voteWeightOrRevert(source, groupId, voterId);
        if (weight == vote.settledWeight) {
            _syncBanList(state, groupId, targetSenderId, totalWeight);
            return true;
        }

        _removeWeight(target, vote.supportBan, vote.settledWeight);
        if (weight == 0) {
            _removeVoteAfterWeightRemoved(state, target, targetSenderId, voterId);
            _settleVote(state, groupId, targetSenderId, voterId, false, 0, totalWeight);
            return true;
        }

        _addWeight(target, vote.supportBan, weight);
        vote.settledWeight = weight;
        _settleVote(state, groupId, targetSenderId, voterId, vote.supportBan, weight, totalWeight);
        return true;
    }

    function _settleVote(
        ChatState storage state,
        uint256 groupId,
        uint256 targetSenderId,
        uint256 voterId,
        bool supportBan,
        uint256 settledWeight,
        uint256 totalWeight
    ) internal {
        TargetState storage target = _targetState(state, targetSenderId);
        emit SenderBanVoteCast({
            groupId: groupId,
            targetSenderId: targetSenderId,
            voterId: voterId,
            supportBan: supportBan,
            settledWeight: settledWeight,
            supportWeight: target.supportWeight,
            opposeWeight: target.opposeWeight
        });
        _syncBanList(state, groupId, targetSenderId, totalWeight);
    }

    function _syncBanList(ChatState storage state, uint256 groupId, uint256 targetSenderId, uint256 totalWeight)
        internal
    {
        bool shouldList = _isTargetBanned(_targetState(state, targetSenderId), totalWeight);
        if (_isBanListed(state, targetSenderId) == shouldList) {
            return;
        }

        _setBanListed(state, targetSenderId, shouldList);
        emit GovSenderBanChanged({
            groupId: groupId,
            targetSenderId: targetSenderId,
            listed: shouldList
        });
    }

    function _sourceOrRevert(uint256 groupId) internal view returns (address source) {
        source = MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId);
        if (source == address(0)) {
            revert GroupNotExist(groupId);
        }
        if (source.code.length == 0) {
            revert BanVoteWeightSourceUnavailable(groupId, source);
        }
    }

    function _sourceHasCode(uint256 groupId) internal view returns (bool) {
        return MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId).code.length != 0;
    }

    function _voteWeightOrRevert(address source, uint256 groupId, uint256 voterId)
        internal
        view
        returns (uint256 weight)
    {
        try IBanVoteWeightSource(source).voteWeightOf(groupId, voterId) returns (uint256 resolved) {
            return resolved;
        } catch {
            revert BanVoteWeightSourceUnavailable(groupId, source);
        }
    }

    function _totalVoteWeightOrRevert(address source, uint256 groupId) internal view returns (uint256) {
        try IBanVoteWeightSource(source).totalVoteWeight(groupId) returns (uint256 resolved) {
            return resolved;
        } catch {
            revert BanVoteWeightSourceUnavailable(groupId, source);
        }
    }

    function _supportExceedsOpposeRatio(TargetState storage target) internal view returns (bool) {
        if (target.opposeWeight == 0) {
            return target.supportWeight > 0;
        }
        uint256 quotient = target.supportWeight / target.opposeWeight;
        if (quotient > MIN_SUPPORT_TO_OPPOSE_MULTIPLIER) {
            return true;
        }
        return quotient == MIN_SUPPORT_TO_OPPOSE_MULTIPLIER && target.supportWeight % target.opposeWeight != 0;
    }

    function _isTargetBanned(TargetState storage target, uint256 totalWeight) internal view returns (bool) {
        if (totalWeight == 0) {
            return false;
        }
        if (!_supportExceedsOpposeRatio(target)) {
            return false;
        }
        return target.supportWeight * PRECISION >= totalWeight * BAN_THRESHOLD_RATIO;
    }

    function _requireTarget(uint256 targetSenderId) internal pure {
        if (targetSenderId == 0) {
            revert ZeroTargetSenderId();
        }
    }

    function _targetState(ChatState storage state, uint256 targetSenderId) internal view returns (TargetState storage) {
        return state.senderIdTargetStates[targetSenderId];
    }

    function _removeVote(ChatState storage state, TargetState storage target, uint256 targetSenderId, uint256 voterId)
        internal
    {
        VoteState storage vote = target.votes[voterId];
        _removeWeight(target, vote.supportBan, vote.settledWeight);
        _removeVoteAfterWeightRemoved(state, target, targetSenderId, voterId);
    }

    function _removeVoteAfterWeightRemoved(
        ChatState storage state,
        TargetState storage target,
        uint256 targetSenderId,
        uint256 voterId
    ) internal {
        delete target.votes[voterId];
        target.voters.remove(voterId);
        if (target.voters.count() == 0) {
            state.senderIdTargets.remove(targetSenderId);
        }
    }

    function _isBanListed(ChatState storage state, uint256 targetSenderId) internal view returns (bool) {
        return state.senderIdBanList.contains(targetSenderId);
    }

    function _setBanListed(ChatState storage state, uint256 targetSenderId, bool listed) internal {
        if (listed) {
            state.senderIdBanList.add(targetSenderId);
        } else {
            state.senderIdBanList.remove(targetSenderId);
        }
    }

    function _addWeight(TargetState storage target, bool supportBan, uint256 weight) internal {
        if (supportBan) {
            target.supportWeight += weight;
        } else {
            target.opposeWeight += weight;
        }
    }

    function _removeWeight(TargetState storage target, bool supportBan, uint256 weight) internal {
        if (supportBan) {
            target.supportWeight -= weight;
        } else {
            target.opposeWeight -= weight;
        }
    }

    function _votersPage(TargetState storage target, uint256 offset, uint256 limit)
        internal
        view
        returns (uint256[] memory voterIds, uint256[] memory supportWeights, uint256[] memory opposeWeights)
    {
        (voterIds,) = target.voters.values(offset, limit, false);
        uint256 count = voterIds.length;
        supportWeights = new uint256[](count);
        opposeWeights = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            VoteState storage vote = target.votes[voterIds[i]];
            (supportWeights[i], opposeWeights[i]) = _voteWeights(vote);
        }
    }

    function _voteWeights(VoteState storage vote) internal view returns (uint256 supportWeight, uint256 opposeWeight) {
        if (vote.settledWeight == 0) {
            return (0, 0);
        }
        if (vote.supportBan) {
            return (vote.settledWeight, 0);
        }
        return (0, vote.settledWeight);
    }
}
