// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IBanVoteWeightSource} from "../../interfaces/sources/ban/IBanVoteWeightSource.sol";
import {IGovVotedBanSource} from "../../interfaces/sources/ban/IGovVotedBanSource.sol";
import {MemberOwner} from "../../MemberOwner.sol";
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
        uint256 stateVersion;
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

    function stateVersion(uint256 groupId) external view returns (uint256) {
        return _states[groupId].stateVersion;
    }

    modifier onlyVoterOwner(uint256 voterId) {
        if (IMemberNFT(GROUP_ADDRESS).ownerOf(voterId) != msg.sender) {
            revert NotMemberOwner(voterId);
        }
        _;
    }

    function _setSenderIdVote(uint256 groupId, uint256 targetSenderId, uint256 voterId, bool supportBan) internal {
        uint256 newVersion = _setVoteIfChanged(groupId, targetSenderId, voterId, supportBan, 0);
        if (newVersion == 0) {
            revert VoteUnchanged(groupId, targetSenderId, voterId);
        }
        _emitChangeStateVersion(groupId, newVersion);
    }

    function _setVoteIfChanged(
        uint256 groupId,
        uint256 targetSenderId,
        uint256 voterId,
        bool supportBan,
        uint256 newVersion
    ) internal returns (uint256) {
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
            return _syncBanList(state, groupId, targetSenderId, totalWeight, newVersion);
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
        newVersion = _ensureStateVersion(state, newVersion);
        _emitSetVote(state, groupId, targetSenderId, voterId, supportBan, weight, newVersion);
        newVersion = _syncBanList(state, groupId, targetSenderId, totalWeight, newVersion);
        return newVersion;
    }

    function _clearSenderIdVote(uint256 groupId, uint256 targetSenderId, uint256 voterId) internal {
        uint256 newVersion = _clearVoteIfFound(groupId, targetSenderId, voterId, 0);
        if (newVersion == 0) {
            revert VoteNotFound(groupId, targetSenderId, voterId);
        }
        _emitChangeStateVersion(groupId, newVersion);
    }

    function _clearVoteIfFound(uint256 groupId, uint256 targetSenderId, uint256 voterId, uint256 newVersion)
        internal
        returns (uint256)
    {
        _requireTarget(targetSenderId);
        address source = _sourceOrRevert(groupId);
        uint256 totalWeight = _totalVoteWeightOrRevert(source, groupId);

        ChatState storage state = _states[groupId];
        TargetState storage target = _targetState(state, targetSenderId);
        VoteState storage vote = target.votes[voterId];
        if (vote.settledWeight == 0) {
            return newVersion;
        }

        _removeVote(state, target, targetSenderId, voterId);
        newVersion = _ensureStateVersion(state, newVersion);
        _emitSetVote(state, groupId, targetSenderId, voterId, false, 0, newVersion);
        newVersion = _syncBanList(state, groupId, targetSenderId, totalWeight, newVersion);
        return newVersion;
    }

    function _refreshSenderIdVote(uint256 groupId, uint256 targetSenderId, uint256 voterId) internal {
        (bool found, uint256 newVersion) = _refreshVoteIfFound(groupId, targetSenderId, voterId, 0);
        if (!found) {
            revert VoteNotFound(groupId, targetSenderId, voterId);
        }
        _emitChangeStateVersionIfChanged(groupId, newVersion);
    }

    function _refreshVoteIfFound(uint256 groupId, uint256 targetSenderId, uint256 voterId, uint256 newVersion)
        internal
        returns (bool found, uint256)
    {
        _requireTarget(targetSenderId);
        address source = _sourceOrRevert(groupId);
        uint256 totalWeight = _totalVoteWeightOrRevert(source, groupId);

        ChatState storage state = _states[groupId];
        TargetState storage target = _targetState(state, targetSenderId);
        VoteState storage vote = target.votes[voterId];
        if (vote.settledWeight == 0) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, newVersion);
        }

        uint256 weight = _voteWeightOrRevert(source, groupId, voterId);
        if (weight == vote.settledWeight) {
            newVersion = _syncBanList(state, groupId, targetSenderId, totalWeight, newVersion);
            // forge-lint: disable-next-item(boolean-cst)
            return (true, newVersion);
        }

        _removeWeight(target, vote.supportBan, vote.settledWeight);
        if (weight == 0) {
            _removeVoteAfterWeightRemoved(state, target, targetSenderId, voterId);
            newVersion = _ensureStateVersion(state, newVersion);
            _emitSetVote(state, groupId, targetSenderId, voterId, false, 0, newVersion);
            newVersion = _syncBanList(state, groupId, targetSenderId, totalWeight, newVersion);
            // forge-lint: disable-next-item(boolean-cst)
            return (true, newVersion);
        }

        _addWeight(target, vote.supportBan, weight);
        vote.settledWeight = weight;
        newVersion = _ensureStateVersion(state, newVersion);
        _emitSetVote(state, groupId, targetSenderId, voterId, vote.supportBan, weight, newVersion);
        newVersion = _syncBanList(state, groupId, targetSenderId, totalWeight, newVersion);
        // forge-lint: disable-next-item(boolean-cst)
        return (true, newVersion);
    }

    function _ensureStateVersion(ChatState storage state, uint256 newVersion) internal returns (uint256) {
        if (newVersion == 0) {
            newVersion = ++state.stateVersion;
        }
        return newVersion;
    }

    function _emitChangeStateVersion(uint256 groupId, uint256 newVersion) internal {
        emit ChangeStateVersion(groupId, newVersion);
    }

    function _emitChangeStateVersionIfChanged(uint256 groupId, uint256 newVersion) internal {
        if (newVersion != 0) {
            emit ChangeStateVersion(groupId, newVersion);
        }
    }

    function _emitSetVote(
        ChatState storage state,
        uint256 groupId,
        uint256 targetSenderId,
        uint256 voterId,
        bool supportBan,
        uint256 settledWeight,
        uint256 newVersion
    ) internal {
        TargetState storage target = _targetState(state, targetSenderId);
        emit SetSenderIdBanVote(
            groupId,
            targetSenderId,
            voterId,
            supportBan,
            settledWeight,
            target.supportWeight,
            target.opposeWeight,
            newVersion
        );
    }

    function _syncBanList(
        ChatState storage state,
        uint256 groupId,
        uint256 targetSenderId,
        uint256 totalWeight,
        uint256 newVersion
    ) internal returns (uint256) {
        bool shouldList = _isTargetBanned(_targetState(state, targetSenderId), totalWeight);
        if (_isBanListed(state, targetSenderId) == shouldList) {
            return newVersion;
        }

        newVersion = _ensureStateVersion(state, newVersion);
        _setBanListed(state, targetSenderId, shouldList);
        _emitSetBan(groupId, targetSenderId, shouldList, newVersion);
        return newVersion;
    }

    function _sourceOrRevert(uint256 groupId) internal view returns (address source) {
        source = MemberOwner.ofOrZero(GROUP_ADDRESS, groupId);
        if (source == address(0)) {
            revert GroupNotExist(groupId);
        }
        if (source.code.length == 0) {
            revert BanVoteWeightSourceUnavailable(source);
        }
    }

    function _sourceHasCode(uint256 groupId) internal view returns (bool) {
        return MemberOwner.ofOrZero(GROUP_ADDRESS, groupId).code.length != 0;
    }

    function _voteWeightOrRevert(address source, uint256 groupId, uint256 voterId)
        internal
        view
        returns (uint256 weight)
    {
        try IBanVoteWeightSource(source).voteWeightOf(groupId, voterId) returns (uint256 resolved) {
            return resolved;
        } catch {
            revert BanVoteWeightSourceUnavailable(source);
        }
    }

    function _totalVoteWeightOrRevert(address source, uint256 groupId) internal view returns (uint256) {
        try IBanVoteWeightSource(source).totalVoteWeight(groupId) returns (uint256 resolved) {
            return resolved;
        } catch {
            revert BanVoteWeightSourceUnavailable(source);
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

    function _emitSetBan(uint256 groupId, uint256 targetSenderId, bool listed, uint256 newVersion) internal {
        emit SetSenderIdBan(groupId, targetSenderId, listed, newVersion);
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
