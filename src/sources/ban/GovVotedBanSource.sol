// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20Group} from "../../interfaces/external/ILOVE20Group.sol";

import {IBanVoteWeightSource} from "../../interfaces/sources/ban/IBanVoteWeightSource.sol";
import {IGovVotedBanSource} from "../../interfaces/sources/ban/IGovVotedBanSource.sol";
import {EnumerableSets} from "../../libraries/EnumerableSets.sol";

contract GovVotedBanSource is IGovVotedBanSource {
    using EnumerableSets for EnumerableSets.AddressSet;
    using EnumerableSets for EnumerableSets.UintSet;

    address public immutable GROUP_ADDRESS;
    uint256 public constant PRECISION = 1e18;
    uint256 public immutable MIN_SUPPORT_TO_OPPOSE_RATIO;
    uint256 public immutable BAN_THRESHOLD_RATIO;

    struct VoteState {
        bool supportBan;
        uint256 settledWeight;
    }

    struct TargetState {
        uint256 supportWeight;
        uint256 opposeWeight;
        address[] voters;
        mapping(address => uint256) voterIndexPlusOne;
        mapping(address => VoteState) votes;
    }

    struct ChatState {
        uint256 stateVersion;
        address[] addressTargets;
        mapping(address => uint256) addressTargetIndexPlusOne;
        mapping(address => TargetState) addressTargetStates;
        uint256[] senderIdTargets;
        mapping(uint256 => uint256) senderIdTargetIndexPlusOne;
        mapping(uint256 => TargetState) senderIdTargetStates;
        EnumerableSets.AddressSet addressBanList;
        EnumerableSets.UintSet senderIdBanList;
    }

    enum TargetKind {
        SenderAddress,
        SenderId
    }

    struct TargetKey {
        TargetKind kind;
        address targetAddress;
        uint256 targetSenderId;
    }

    mapping(uint256 => ChatState) internal _states;

    constructor(address groupAddress_, uint256 minSupportToOpposeRatio_, uint256 banThresholdRatio_) {
        if (groupAddress_.code.length == 0) {
            revert GovVotedBanSourceAddressHasNoCode();
        }
        if (minSupportToOpposeRatio_ == 0) {
            revert MinSupportToOpposeRatioZero();
        }
        if (banThresholdRatio_ > PRECISION) {
            revert BanThresholdTooHigh();
        }
        GROUP_ADDRESS = groupAddress_;
        MIN_SUPPORT_TO_OPPOSE_RATIO = minSupportToOpposeRatio_;
        BAN_THRESHOLD_RATIO = banThresholdRatio_;
    }

    function voteBySenderAddress(uint256 groupId, address senderAddress, bool supportBan) external {
        _setAddressVote(groupId, senderAddress, msg.sender, supportBan);
    }

    function clearVoteBySenderAddress(uint256 groupId, address senderAddress) external {
        _clearAddressVote(groupId, senderAddress, msg.sender);
    }

    function refreshVoteBySenderAddress(uint256 groupId, address senderAddress, address voter) external {
        _refreshAddressVote(groupId, senderAddress, voter);
    }

    function voteBySenderId(uint256 groupId, uint256 senderId, bool supportBan) external {
        _setSenderIdVote(groupId, senderId, msg.sender, supportBan);
    }

    function clearVoteBySenderId(uint256 groupId, uint256 senderId) external {
        _clearSenderIdVote(groupId, senderId, msg.sender);
    }

    function refreshVoteBySenderId(uint256 groupId, uint256 senderId, address voter) external {
        _refreshSenderIdVote(groupId, senderId, voter);
    }

    function voteBySender(uint256 groupId, uint256 senderId, address senderAddress, bool supportBan) external {
        _setSenderVote(groupId, senderId, senderAddress, msg.sender, supportBan);
    }

    function clearVoteBySender(uint256 groupId, uint256 senderId, address senderAddress) external {
        _clearSenderVote(groupId, senderId, senderAddress, msg.sender);
    }

    function refreshVoteBySender(uint256 groupId, uint256 senderId, address senderAddress, address voter) external {
        _refreshSenderVote(groupId, senderId, senderAddress, voter);
    }

    function voteWeightsBySenderAddressesByVoter(uint256 groupId, address[] calldata senderAddresses, address voter)
        external
        view
        returns (uint256[] memory supportWeights, uint256[] memory opposeWeights)
    {
        supportWeights = new uint256[](senderAddresses.length);
        opposeWeights = new uint256[](senderAddresses.length);
        if (!_sourceHasCode(groupId)) {
            return (supportWeights, opposeWeights);
        }
        ChatState storage state = _states[groupId];
        for (uint256 i = 0; i < senderAddresses.length; i++) {
            VoteState storage vote = state.addressTargetStates[senderAddresses[i]].votes[voter];
            (supportWeights[i], opposeWeights[i]) = _voteWeights(vote);
        }
    }

    function voteWeightsBySenderIdsByVoter(uint256 groupId, uint256[] calldata senderIds, address voter)
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
            VoteState storage vote = state.senderIdTargetStates[senderIds[i]].votes[voter];
            (supportWeights[i], opposeWeights[i]) = _voteWeights(vote);
        }
    }

    function voteStatusBySenderAddress(uint256 groupId, address senderAddress)
        external
        view
        returns (bool banned, uint256 supportWeight, uint256 opposeWeight)
    {
        if (!_sourceHasCode(groupId)) {
            return (false, 0, 0);
        }
        ChatState storage state = _states[groupId];
        TargetState storage target = state.addressTargetStates[senderAddress];
        return (state.addressBanList.contains(senderAddress), target.supportWeight, target.opposeWeight);
    }

    function voteStatusBySenderId(uint256 groupId, uint256 senderId)
        external
        view
        returns (bool banned, uint256 supportWeight, uint256 opposeWeight)
    {
        if (!_sourceHasCode(groupId)) {
            return (false, 0, 0);
        }
        ChatState storage state = _states[groupId];
        TargetState storage target = state.senderIdTargetStates[senderId];
        return (state.senderIdBanList.contains(senderId), target.supportWeight, target.opposeWeight);
    }

    function votedSenderAddressesCount(uint256 groupId) external view returns (uint256) {
        if (!_sourceHasCode(groupId)) {
            return 0;
        }
        return _states[groupId].addressTargets.length;
    }

    function votedSenderAddresses(uint256 groupId, uint256 offset, uint256 limit)
        external
        view
        returns (
            address[] memory senderAddresses,
            uint256[] memory supportWeights,
            uint256[] memory opposeWeights,
            uint256[] memory voterCounts
        )
    {
        if (!_sourceHasCode(groupId)) {
            return (new address[](0), new uint256[](0), new uint256[](0), new uint256[](0));
        }

        ChatState storage state = _states[groupId];
        uint256 count = _pageCount(state.addressTargets.length, offset, limit);
        senderAddresses = new address[](count);
        supportWeights = new uint256[](count);
        opposeWeights = new uint256[](count);
        voterCounts = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            address senderAddress = state.addressTargets[offset + i];
            TargetState storage target = state.addressTargetStates[senderAddress];
            senderAddresses[i] = senderAddress;
            supportWeights[i] = target.supportWeight;
            opposeWeights[i] = target.opposeWeight;
            voterCounts[i] = target.voters.length;
        }
    }

    function votedSenderIdsCount(uint256 groupId) external view returns (uint256) {
        if (!_sourceHasCode(groupId)) {
            return 0;
        }
        return _states[groupId].senderIdTargets.length;
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
        uint256 count = _pageCount(state.senderIdTargets.length, offset, limit);
        senderIds = new uint256[](count);
        supportWeights = new uint256[](count);
        opposeWeights = new uint256[](count);
        voterCounts = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 senderId = state.senderIdTargets[offset + i];
            TargetState storage target = state.senderIdTargetStates[senderId];
            senderIds[i] = senderId;
            supportWeights[i] = target.supportWeight;
            opposeWeights[i] = target.opposeWeight;
            voterCounts[i] = target.voters.length;
        }
    }

    function votersBySenderAddressCount(uint256 groupId, address senderAddress) external view returns (uint256) {
        if (!_sourceHasCode(groupId)) {
            return 0;
        }
        return _states[groupId].addressTargetStates[senderAddress].voters.length;
    }

    function votersBySenderAddress(uint256 groupId, address senderAddress, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory voters, uint256[] memory supportWeights, uint256[] memory opposeWeights)
    {
        if (!_sourceHasCode(groupId)) {
            return (new address[](0), new uint256[](0), new uint256[](0));
        }
        return _votersPage(_states[groupId].addressTargetStates[senderAddress], offset, limit);
    }

    function votersBySenderIdCount(uint256 groupId, uint256 senderId) external view returns (uint256) {
        if (!_sourceHasCode(groupId)) {
            return 0;
        }
        return _states[groupId].senderIdTargetStates[senderId].voters.length;
    }

    function votersBySenderId(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory voters, uint256[] memory supportWeights, uint256[] memory opposeWeights)
    {
        if (!_sourceHasCode(groupId)) {
            return (new address[](0), new uint256[](0), new uint256[](0));
        }
        return _votersPage(_states[groupId].senderIdTargetStates[senderId], offset, limit);
    }

    function isBanned(uint256 groupId, uint256 senderId, address senderAddress) external view returns (bool) {
        ChatState storage state = _states[groupId];
        return state.addressBanList.contains(senderAddress) || state.senderIdBanList.contains(senderId);
    }

    function isAddressBanned(uint256 groupId, address senderAddress) external view returns (bool) {
        return _states[groupId].addressBanList.contains(senderAddress);
    }

    function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool) {
        return _states[groupId].senderIdBanList.contains(senderId);
    }

    function isAddressBannedBatch(uint256 groupId, address[] calldata senderAddresses)
        external
        view
        returns (bool[] memory banned)
    {
        ChatState storage state = _states[groupId];
        banned = new bool[](senderAddresses.length);
        for (uint256 i = 0; i < senderAddresses.length; i++) {
            banned[i] = state.addressBanList.contains(senderAddresses[i]);
        }
    }

    function isSenderIdBannedBatch(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned)
    {
        ChatState storage state = _states[groupId];
        banned = new bool[](senderIds.length);
        for (uint256 i = 0; i < senderIds.length; i++) {
            banned[i] = state.senderIdBanList.contains(senderIds[i]);
        }
    }

    function voteStatusBySenderAddresses(uint256 groupId, address[] calldata senderAddresses)
        external
        view
        returns (bool[] memory banned, uint256[] memory supportWeights, uint256[] memory opposeWeights)
    {
        ChatState storage state = _states[groupId];
        banned = new bool[](senderAddresses.length);
        supportWeights = new uint256[](senderAddresses.length);
        opposeWeights = new uint256[](senderAddresses.length);
        for (uint256 i = 0; i < senderAddresses.length; i++) {
            address senderAddress = senderAddresses[i];
            TargetState storage target = state.addressTargetStates[senderAddress];
            banned[i] = state.addressBanList.contains(senderAddress);
            supportWeights[i] = target.supportWeight;
            opposeWeights[i] = target.opposeWeight;
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

    function _setAddressVote(uint256 groupId, address targetAddress, address voter, bool supportBan) internal {
        uint256 newVersion =
            _setVoteIfChanged(groupId, TargetKey(TargetKind.SenderAddress, targetAddress, 0), voter, supportBan, 0);
        if (newVersion == 0) {
            revert VoteUnchanged();
        }
        _emitChangeStateVersion(groupId, newVersion);
    }

    function _setSenderIdVote(uint256 groupId, uint256 targetSenderId, address voter, bool supportBan) internal {
        uint256 newVersion =
            _setVoteIfChanged(groupId, TargetKey(TargetKind.SenderId, address(0), targetSenderId), voter, supportBan, 0);
        if (newVersion == 0) {
            revert VoteUnchanged();
        }
        _emitChangeStateVersion(groupId, newVersion);
    }

    function _setVoteIfChanged(
        uint256 groupId,
        TargetKey memory key,
        address voter,
        bool supportBan,
        uint256 newVersion
    ) internal returns (uint256) {
        _requireTarget(key);
        address source = _sourceOrRevert(groupId);
        uint256 weight = _voteWeightOrRevert(source, groupId, voter);
        if (weight == 0) {
            revert VoteWeightZero();
        }
        uint256 totalWeight = _totalVoteWeightOrRevert(source, groupId);

        ChatState storage state = _states[groupId];
        TargetState storage target = _targetState(state, key);
        VoteState storage vote = target.votes[voter];
        bool voteExists = vote.settledWeight != 0;
        if (voteExists && vote.supportBan == supportBan && vote.settledWeight == weight) {
            return _syncBanList(state, groupId, key, totalWeight, newVersion);
        }

        if (!voteExists) {
            _addTarget(state, key);
            _addVoter(target, voter);
        } else {
            _removeWeight(target, vote.supportBan, vote.settledWeight);
        }

        _addWeight(target, supportBan, weight);
        vote.supportBan = supportBan;
        vote.settledWeight = weight;
        newVersion = _ensureStateVersion(state, newVersion);
        _emitSetVote(state, groupId, key, voter, supportBan, weight, newVersion);
        newVersion = _syncBanList(state, groupId, key, totalWeight, newVersion);
        return newVersion;
    }

    function _clearAddressVote(uint256 groupId, address targetAddress, address voter) internal {
        uint256 newVersion = _clearVoteIfFound(groupId, TargetKey(TargetKind.SenderAddress, targetAddress, 0), voter, 0);
        if (newVersion == 0) {
            revert VoteNotFound();
        }
        _emitChangeStateVersion(groupId, newVersion);
    }

    function _clearSenderIdVote(uint256 groupId, uint256 targetSenderId, address voter) internal {
        uint256 newVersion =
            _clearVoteIfFound(groupId, TargetKey(TargetKind.SenderId, address(0), targetSenderId), voter, 0);
        if (newVersion == 0) {
            revert VoteNotFound();
        }
        _emitChangeStateVersion(groupId, newVersion);
    }

    function _clearVoteIfFound(uint256 groupId, TargetKey memory key, address voter, uint256 newVersion)
        internal
        returns (uint256)
    {
        _requireTarget(key);
        address source = _sourceOrRevert(groupId);
        uint256 totalWeight = _totalVoteWeightOrRevert(source, groupId);

        ChatState storage state = _states[groupId];
        TargetState storage target = _targetState(state, key);
        VoteState storage vote = target.votes[voter];
        if (vote.settledWeight == 0) {
            return newVersion;
        }

        _removeVote(state, target, key, voter);
        newVersion = _ensureStateVersion(state, newVersion);
        _emitSetVote(state, groupId, key, voter, false, 0, newVersion);
        newVersion = _syncBanList(state, groupId, key, totalWeight, newVersion);
        return newVersion;
    }

    function _refreshAddressVote(uint256 groupId, address targetAddress, address voter) internal {
        (bool found, uint256 newVersion) =
            _refreshVoteIfFound(groupId, TargetKey(TargetKind.SenderAddress, targetAddress, 0), voter, 0);
        if (!found) {
            revert VoteNotFound();
        }
        _emitChangeStateVersionIfChanged(groupId, newVersion);
    }

    function _refreshSenderIdVote(uint256 groupId, uint256 targetSenderId, address voter) internal {
        (bool found, uint256 newVersion) =
            _refreshVoteIfFound(groupId, TargetKey(TargetKind.SenderId, address(0), targetSenderId), voter, 0);
        if (!found) {
            revert VoteNotFound();
        }
        _emitChangeStateVersionIfChanged(groupId, newVersion);
    }

    function _refreshVoteIfFound(uint256 groupId, TargetKey memory key, address voter, uint256 newVersion)
        internal
        returns (bool found, uint256)
    {
        _requireTarget(key);
        address source = _sourceOrRevert(groupId);
        uint256 totalWeight = _totalVoteWeightOrRevert(source, groupId);

        ChatState storage state = _states[groupId];
        TargetState storage target = _targetState(state, key);
        VoteState storage vote = target.votes[voter];
        if (vote.settledWeight == 0) {
            return (false, newVersion);
        }

        uint256 weight = _voteWeightOrRevert(source, groupId, voter);
        if (weight == vote.settledWeight) {
            newVersion = _syncBanList(state, groupId, key, totalWeight, newVersion);
            return (true, newVersion);
        }

        _removeWeight(target, vote.supportBan, vote.settledWeight);
        if (weight == 0) {
            _removeVoteAfterWeightRemoved(state, target, key, voter);
            newVersion = _ensureStateVersion(state, newVersion);
            _emitSetVote(state, groupId, key, voter, false, 0, newVersion);
            newVersion = _syncBanList(state, groupId, key, totalWeight, newVersion);
            return (true, newVersion);
        }

        _addWeight(target, vote.supportBan, weight);
        vote.settledWeight = weight;
        newVersion = _ensureStateVersion(state, newVersion);
        _emitSetVote(state, groupId, key, voter, vote.supportBan, weight, newVersion);
        newVersion = _syncBanList(state, groupId, key, totalWeight, newVersion);
        return (true, newVersion);
    }

    function _setSenderVote(
        uint256 groupId,
        uint256 targetSenderId,
        address targetAddress,
        address voter,
        bool supportBan
    ) internal {
        _requireSenderTarget(targetSenderId, targetAddress);
        uint256 newVersion =
            _setVoteIfChanged(groupId, TargetKey(TargetKind.SenderAddress, targetAddress, 0), voter, supportBan, 0);
        newVersion = _setVoteIfChanged(
            groupId, TargetKey(TargetKind.SenderId, address(0), targetSenderId), voter, supportBan, newVersion
        );
        if (newVersion == 0) {
            revert VoteUnchanged();
        }
        _emitChangeStateVersion(groupId, newVersion);
    }

    function _clearSenderVote(uint256 groupId, uint256 targetSenderId, address targetAddress, address voter) internal {
        _requireSenderTarget(targetSenderId, targetAddress);
        uint256 newVersion = _clearVoteIfFound(groupId, TargetKey(TargetKind.SenderAddress, targetAddress, 0), voter, 0);
        newVersion =
            _clearVoteIfFound(groupId, TargetKey(TargetKind.SenderId, address(0), targetSenderId), voter, newVersion);
        if (newVersion == 0) {
            revert VoteNotFound();
        }
        _emitChangeStateVersion(groupId, newVersion);
    }

    function _refreshSenderVote(uint256 groupId, uint256 targetSenderId, address targetAddress, address voter)
        internal
    {
        _requireSenderTarget(targetSenderId, targetAddress);
        (bool addressFound, uint256 newVersion) =
            _refreshVoteIfFound(groupId, TargetKey(TargetKind.SenderAddress, targetAddress, 0), voter, 0);
        (bool senderIdFound, uint256 newVersion2) =
            _refreshVoteIfFound(groupId, TargetKey(TargetKind.SenderId, address(0), targetSenderId), voter, newVersion);
        if (!addressFound && !senderIdFound) {
            revert VoteNotFound();
        }
        _emitChangeStateVersionIfChanged(groupId, newVersion2);
    }

    function _requireSenderTarget(uint256 targetSenderId, address targetAddress) internal pure {
        if (targetSenderId == 0) {
            revert TargetSenderIdZero();
        }
        if (targetAddress == address(0)) {
            revert TargetAddressZero();
        }
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
        TargetKey memory key,
        address voter,
        bool supportBan,
        uint256 settledWeight,
        uint256 newVersion
    ) internal {
        TargetState storage target = _targetState(state, key);
        if (key.kind == TargetKind.SenderAddress) {
            emit SetAddressBanVote(
                groupId,
                key.targetAddress,
                voter,
                supportBan,
                settledWeight,
                target.supportWeight,
                target.opposeWeight,
                newVersion
            );
        } else {
            emit SetSenderIdBanVote(
                groupId,
                key.targetSenderId,
                voter,
                supportBan,
                settledWeight,
                target.supportWeight,
                target.opposeWeight,
                newVersion
            );
        }
    }

    function _syncBanList(
        ChatState storage state,
        uint256 groupId,
        TargetKey memory key,
        uint256 totalWeight,
        uint256 newVersion
    ) internal returns (uint256) {
        bool shouldList = _isTargetBanned(_targetState(state, key), totalWeight);
        if (_isBanListed(state, key) == shouldList) {
            return newVersion;
        }

        newVersion = _ensureStateVersion(state, newVersion);
        _setBanListed(state, key, shouldList);
        _emitSetBan(groupId, key, shouldList, newVersion);
        return newVersion;
    }

    function _sourceOrRevert(uint256 groupId) internal view returns (address source) {
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            source = resolved;
        } catch {
            revert BanVoteWeightSourceUnavailable();
        }
        if (source.code.length == 0) {
            revert BanVoteWeightSourceUnavailable();
        }
    }

    function _sourceHasCode(uint256 groupId) internal view returns (bool) {
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address source) {
            return source.code.length != 0;
        } catch {
            return false;
        }
    }

    function _voteWeightOrRevert(address source, uint256 groupId, address voter)
        internal
        view
        returns (uint256 weight)
    {
        try IBanVoteWeightSource(source).voteWeightOf(groupId, voter) returns (uint256 resolved) {
            return resolved;
        } catch {
            revert BanVoteWeightSourceUnavailable();
        }
    }

    function _totalVoteWeightOrRevert(address source, uint256 groupId) internal view returns (uint256) {
        try IBanVoteWeightSource(source).totalVoteWeight(groupId) returns (uint256 resolved) {
            return resolved;
        } catch {
            revert BanVoteWeightSourceUnavailable();
        }
    }

    function _supportExceedsOpposeRatio(TargetState storage target) internal view returns (bool) {
        if (target.opposeWeight == 0) {
            return target.supportWeight > 0;
        }
        uint256 quotient = target.supportWeight / target.opposeWeight;
        if (quotient > MIN_SUPPORT_TO_OPPOSE_RATIO) {
            return true;
        }
        return quotient == MIN_SUPPORT_TO_OPPOSE_RATIO && target.supportWeight % target.opposeWeight != 0;
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

    function _requireTarget(TargetKey memory key) internal pure {
        if (key.kind == TargetKind.SenderAddress) {
            if (key.targetAddress == address(0)) {
                revert TargetAddressZero();
            }
        } else if (key.targetSenderId == 0) {
            revert TargetSenderIdZero();
        }
    }

    function _targetState(ChatState storage state, TargetKey memory key) internal view returns (TargetState storage) {
        if (key.kind == TargetKind.SenderAddress) {
            return state.addressTargetStates[key.targetAddress];
        }
        return state.senderIdTargetStates[key.targetSenderId];
    }

    function _addTarget(ChatState storage state, TargetKey memory key) internal {
        if (key.kind == TargetKind.SenderAddress) {
            _addAddressTarget(state, key.targetAddress);
        } else {
            _addSenderIdTarget(state, key.targetSenderId);
        }
    }

    function _removeTarget(ChatState storage state, TargetKey memory key) internal {
        if (key.kind == TargetKind.SenderAddress) {
            _removeAddressTarget(state, key.targetAddress);
        } else {
            _removeSenderIdTarget(state, key.targetSenderId);
        }
    }

    function _removeVote(ChatState storage state, TargetState storage target, TargetKey memory key, address voter)
        internal
    {
        VoteState storage vote = target.votes[voter];
        _removeWeight(target, vote.supportBan, vote.settledWeight);
        _removeVoteAfterWeightRemoved(state, target, key, voter);
    }

    function _removeVoteAfterWeightRemoved(
        ChatState storage state,
        TargetState storage target,
        TargetKey memory key,
        address voter
    ) internal {
        delete target.votes[voter];
        _removeVoter(target, voter);
        if (target.voters.length == 0) {
            _removeTarget(state, key);
        }
    }

    function _isBanListed(ChatState storage state, TargetKey memory key) internal view returns (bool) {
        if (key.kind == TargetKind.SenderAddress) {
            return state.addressBanList.contains(key.targetAddress);
        }
        return state.senderIdBanList.contains(key.targetSenderId);
    }

    function _setBanListed(ChatState storage state, TargetKey memory key, bool listed) internal {
        if (key.kind == TargetKind.SenderAddress) {
            if (listed) {
                state.addressBanList.add(key.targetAddress);
            } else {
                state.addressBanList.remove(key.targetAddress);
            }
        } else if (listed) {
            state.senderIdBanList.add(key.targetSenderId);
        } else {
            state.senderIdBanList.remove(key.targetSenderId);
        }
    }

    function _emitSetBan(uint256 groupId, TargetKey memory key, bool listed, uint256 newVersion) internal {
        if (key.kind == TargetKind.SenderAddress) {
            emit SetAddressBan(groupId, key.targetAddress, listed, newVersion);
        } else {
            emit SetSenderIdBan(groupId, key.targetSenderId, listed, newVersion);
        }
    }

    function _addAddressTarget(ChatState storage state, address targetAddress) internal {
        if (state.addressTargetIndexPlusOne[targetAddress] != 0) {
            return;
        }
        state.addressTargets.push(targetAddress);
        state.addressTargetIndexPlusOne[targetAddress] = state.addressTargets.length;
    }

    function _removeAddressTarget(ChatState storage state, address targetAddress) internal {
        uint256 indexPlusOne = state.addressTargetIndexPlusOne[targetAddress];
        if (indexPlusOne == 0) {
            return;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = state.addressTargets.length - 1;
        if (index != lastIndex) {
            address last = state.addressTargets[lastIndex];
            state.addressTargets[index] = last;
            state.addressTargetIndexPlusOne[last] = indexPlusOne;
        }
        state.addressTargets.pop();
        delete state.addressTargetIndexPlusOne[targetAddress];
    }

    function _addSenderIdTarget(ChatState storage state, uint256 targetSenderId) internal {
        if (state.senderIdTargetIndexPlusOne[targetSenderId] != 0) {
            return;
        }
        state.senderIdTargets.push(targetSenderId);
        state.senderIdTargetIndexPlusOne[targetSenderId] = state.senderIdTargets.length;
    }

    function _removeSenderIdTarget(ChatState storage state, uint256 targetSenderId) internal {
        uint256 indexPlusOne = state.senderIdTargetIndexPlusOne[targetSenderId];
        if (indexPlusOne == 0) {
            return;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = state.senderIdTargets.length - 1;
        if (index != lastIndex) {
            uint256 last = state.senderIdTargets[lastIndex];
            state.senderIdTargets[index] = last;
            state.senderIdTargetIndexPlusOne[last] = indexPlusOne;
        }
        state.senderIdTargets.pop();
        delete state.senderIdTargetIndexPlusOne[targetSenderId];
    }

    function _addVoter(TargetState storage target, address voter) internal {
        if (target.voterIndexPlusOne[voter] != 0) {
            return;
        }
        target.voters.push(voter);
        target.voterIndexPlusOne[voter] = target.voters.length;
    }

    function _removeVoter(TargetState storage target, address voter) internal {
        uint256 indexPlusOne = target.voterIndexPlusOne[voter];
        if (indexPlusOne == 0) {
            return;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = target.voters.length - 1;
        if (index != lastIndex) {
            address last = target.voters[lastIndex];
            target.voters[index] = last;
            target.voterIndexPlusOne[last] = indexPlusOne;
        }
        target.voters.pop();
        delete target.voterIndexPlusOne[voter];
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
        returns (address[] memory voters, uint256[] memory supportWeights, uint256[] memory opposeWeights)
    {
        uint256 count = _pageCount(target.voters.length, offset, limit);
        voters = new address[](count);
        supportWeights = new uint256[](count);
        opposeWeights = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            address voter = target.voters[offset + i];
            VoteState storage vote = target.votes[voter];
            voters[i] = voter;
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

    function _pageCount(uint256 total, uint256 offset, uint256 limit) internal pure returns (uint256) {
        if (limit == 0 || offset >= total) {
            return 0;
        }

        uint256 remaining = total - offset;
        return remaining < limit ? remaining : limit;
    }
}
