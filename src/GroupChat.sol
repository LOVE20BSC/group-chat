// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChat} from "./interfaces/IGroupChat.sol";
import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";
import {IGroupChatDelegate} from "./interfaces/IGroupChatDelegate.sol";
import {IAfterPostPlugin} from "./interfaces/plugins/IAfterPostPlugin.sol";
import {IBeforePostPlugin} from "./interfaces/plugins/IBeforePostPlugin.sol";
import {IPostBanSource} from "./interfaces/sources/IPostBanSource.sol";
import {IPostScopeSource} from "./interfaces/sources/IPostScopeSource.sol";
import {MemberOwner} from "./MemberOwner.sol";
import {IPhase} from "@core/interfaces/IPhase.sol";
import {Pagination} from "@libs/Pagination.sol";

contract GroupChat is IGroupChat {
    uint256 public immutable MAX_CONTENT_LENGTH;
    uint256 public immutable MAX_MENTIONED_SENDER_IDS;

    address public immutable GROUP_ADMIN_ADDRESS;
    address public immutable GROUP_ADDRESS;
    address public immutable GROUP_DELEGATE_ADDRESS;
    address public immutable PHASE_ADDRESS;

    struct ChatConfig {
        bool activated;
        bool postingAllowed;
        address firstActivatedOwner;
        uint256 firstActivatedBlockNumber;
        uint256 firstActivatedTimestamp;
        address scopeSource;
        address banSource;
        address beforePostPlugin;
        address afterPostPlugin;
    }

    struct RoundState {
        uint256 startIndexPlusOne;
        uint256 endIndex;
    }

    struct StoredMessage {
        uint256 senderId;
        address senderAddress;
        string content;
        uint256 blockNumber;
        uint256 timestamp;
        uint256 round;
        uint256[] mentionedSenderIds;
        bool mentionAll;
        uint256 quotedMessageId;
    }

    mapping(uint256 => ChatConfig) internal _chatConfigs;
    mapping(uint256 => StoredMessage[]) internal _messagesByChat;
    mapping(uint256 => mapping(uint256 => uint256[])) internal _senderMessageIndexes;
    mapping(uint256 => mapping(uint256 => uint256[])) internal _mentionMessageIndexes;
    mapping(uint256 => uint256[]) internal _mentionAllMessageIndexes;
    mapping(uint256 => uint256[]) internal _senderIdsByChat;
    mapping(uint256 => mapping(uint256 => RoundState)) internal _roundStates;
    mapping(uint256 => uint256[]) internal _roundListByChat;
    uint256[] internal _groupIds;

    uint256 internal _entered;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(
        address groupAdmin_,
        address phaseAddress_,
        uint256 maxContentLength_,
        uint256 maxMentionedSenderIds_
    ) {
        address groupDelegate = IGroupAdmin(groupAdmin_).GROUP_DELEGATE_ADDRESS();
        address groupAddress = IGroupAdmin(groupAdmin_).GROUP_ADDRESS();
        GROUP_ADMIN_ADDRESS = groupAdmin_;
        GROUP_DELEGATE_ADDRESS = groupDelegate;
        GROUP_ADDRESS = groupAddress;
        PHASE_ADDRESS = phaseAddress_;
        MAX_CONTENT_LENGTH = maxContentLength_;
        MAX_MENTIONED_SENDER_IDS = maxMentionedSenderIds_;
    }

    modifier nonReentrant() {
        if (_entered != 0) {
            revert Reentrant();
        }
        _entered = 1;
        _;
        _entered = 0;
    }

    modifier onlySenderOwner(uint256 senderId) {
        if (MemberOwner.ownerOf(GROUP_ADDRESS, senderId) != msg.sender) {
            revert NotMemberOwner(senderId);
        }
        _;
    }

    modifier onlyChatOwner(uint256 groupId) {
        if (msg.sender != _ownerOfOrRevertGroupNotExist(groupId)) {
            revert NotGroupOwner(groupId);
        }
        _;
    }

    function activateChat(
        uint256 groupId,
        address scopeSource_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_
    ) external nonReentrant onlyChatOwner(groupId) {
        address owner = _ownerOfOrRevertGroupNotExist(groupId);

        ChatConfig storage config = _chatConfigs[groupId];
        if (config.activated) {
            revert ChatAlreadyActivated(groupId);
        }

        _validateSourceAddress(scopeSource_);
        _validateSourceAddress(banSource_);
        _validatePluginAddress(beforePostPlugin_);
        _validatePluginAddress(afterPostPlugin_);

        config.firstActivatedOwner = owner;
        config.firstActivatedBlockNumber = block.number;
        config.firstActivatedTimestamp = block.timestamp;
        _groupIds.push(groupId);

        config.activated = true;
        config.postingAllowed = true;
        config.scopeSource = scopeSource_;
        config.banSource = banSource_;
        config.beforePostPlugin = beforePostPlugin_;
        config.afterPostPlugin = afterPostPlugin_;

        if (scopeSource_ != address(0)) {
            emit SetScopeSource(groupId, scopeSource_, groupId, msg.sender, address(0));
        }
        if (banSource_ != address(0)) {
            emit SetBanSource(groupId, banSource_, groupId, msg.sender, address(0));
        }
        if (beforePostPlugin_ != address(0)) {
            emit SetBeforePostPlugin(groupId, beforePostPlugin_, groupId, msg.sender, address(0));
        }
        if (afterPostPlugin_ != address(0)) {
            emit SetAfterPostPlugin(groupId, afterPostPlugin_, groupId, msg.sender, address(0));
        }
        emit Activate(groupId, groupId, owner);
    }

    function setPostingAllowed(uint256 groupId, uint256 operatorId, bool postingAllowed_)
        external
        nonReentrant
        onlyOwnerOrDelegate(groupId, operatorId)
    {
        _requireActivated(groupId);

        ChatConfig storage config = _chatConfigs[groupId];
        if (config.postingAllowed == postingAllowed_) {
            return;
        }

        // forge-lint: disable-next-item(missing-events-access-control)
        config.postingAllowed = postingAllowed_;
        emit SetPostingAllowed(groupId, operatorId, msg.sender, postingAllowed_);
    }

    function setScopeSource(
        uint256 groupId,
        uint256 operatorId,
        address sourceAddress
    ) external nonReentrant onlyOwnerOrDelegate(groupId, operatorId) {
        _setSource(groupId, operatorId, sourceAddress, true);
    }

    function setBanSource(
        uint256 groupId,
        uint256 operatorId,
        address sourceAddress
    ) external nonReentrant onlyOwnerOrDelegate(groupId, operatorId) {
        _setSource(groupId, operatorId, sourceAddress, false);
    }

    function setBeforePostPlugin(
        uint256 groupId,
        uint256 operatorId,
        address pluginAddress
    ) external nonReentrant onlyOwnerOrDelegate(groupId, operatorId) {
        _setPostPlugin(groupId, operatorId, pluginAddress, true);
    }

    function setAfterPostPlugin(
        uint256 groupId,
        uint256 operatorId,
        address pluginAddress
    ) external nonReentrant onlyOwnerOrDelegate(groupId, operatorId) {
        _setPostPlugin(groupId, operatorId, pluginAddress, false);
    }

    function post(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId
    ) external nonReentrant onlySenderOwner(senderId) {
        _post(groupId, senderId, content, mentionedSenderIds, mentionAll, quotedMessageId);
    }

    function _post(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId
    ) internal {
        _requireExistingGroup(groupId);
        ChatConfig storage config = _chatConfigs[groupId];
        if (!config.activated) {
            revert ChatNotActivated(groupId);
        }
        if (!config.postingAllowed) {
            revert PostingNotAllowed(groupId);
        }

        if (bytes(content).length == 0) {
            revert ContentEmpty();
        }
        if (bytes(content).length > MAX_CONTENT_LENGTH) {
            revert ContentTooLong(bytes(content).length, MAX_CONTENT_LENGTH);
        }
        _validateMentionedSenderIds(mentionedSenderIds);
        uint256 delegateId = IGroupChatDelegate(GROUP_DELEGATE_ADDRESS).delegateIdOf(groupId);
        if (mentionAll) {
            _requireMentionAllOperator(groupId, senderId, delegateId);
        }
        _validateQuotedMessageId(groupId, quotedMessageId);

        uint256 round = currentRound();
        _requirePostSources(config, groupId, senderId, delegateId);
        if (config.beforePostPlugin != address(0)) {
            IBeforePostPlugin(config.beforePostPlugin).beforePost(
                groupId, senderId, msg.sender, content, mentionedSenderIds, mentionAll, quotedMessageId
            );
        }

        uint256 messageIndex =
            _storeMessage(groupId, senderId, content, mentionedSenderIds, mentionAll, quotedMessageId, round);

        if (_senderMessageIndexes[groupId][senderId].length == 0) {
            _senderIdsByChat[groupId].push(senderId);
        }
        _senderMessageIndexes[groupId][senderId].push(messageIndex);

        _recordRound(groupId, round, messageIndex);

        emit PostMessage(groupId, senderId, msg.sender, round, messageIndex + 1);
        for (uint256 i = 0; i < mentionedSenderIds.length; i++) {
            emit MentionSenderId(groupId, mentionedSenderIds[i], messageIndex + 1);
        }
        if (mentionAll) {
            emit MentionAll(groupId, messageIndex + 1);
        }

        if (config.afterPostPlugin != address(0)) {
            try IAfterPostPlugin(config.afterPostPlugin).afterPost(
                groupId,
                senderId,
                msg.sender,
                content,
                mentionedSenderIds,
                mentionAll,
                quotedMessageId,
                messageIndex + 1,
                block.number,
                block.timestamp
            ) {} catch (bytes memory err) {
                bytes4 errorSelector = bytes4(0);
                if (err.length >= 4) {
                    assembly ("memory-safe") {
                        errorSelector := mload(add(err, 0x20))
                    }
                }
                emit FailAfterPostPlugin(
                    groupId,
                    messageIndex + 1,
                    config.afterPostPlugin,
                    round,
                    keccak256(err),
                    err.length,
                    errorSelector
                );
            }
        }
    }

    function chatInfo(uint256 groupId) external view returns (ChatInfo memory) {
        return _chatInfo(groupId);
    }

    function chatInfos(uint256[] calldata groupIds_) external view returns (ChatInfo[] memory) {
        ChatInfo[] memory result = new ChatInfo[](groupIds_.length);

        for (uint256 i = 0; i < groupIds_.length; i++) {
            result[i] = _chatInfo(groupIds_[i]);
        }

        return result;
    }

    function _chatInfo(uint256 groupId) internal view returns (ChatInfo memory) {
        address owner = _ownerOfOrRevertGroupNotExist(groupId);
        ChatConfig storage config = _chatConfigs[groupId];
        return ChatInfo({
            groupId: groupId,
            owner: owner,
            activated: config.activated,
            postingAllowed: config.postingAllowed,
            scopeSource: config.scopeSource,
            banSource: config.banSource,
            beforePostPlugin: config.beforePostPlugin,
            afterPostPlugin: config.afterPostPlugin,
            firstActivatedOwner: config.firstActivatedOwner,
            firstActivatedBlockNumber: config.firstActivatedBlockNumber,
            firstActivatedTimestamp: config.firstActivatedTimestamp
        });
    }

    function postingAllowed(uint256 groupId) external view returns (bool) {
        _requireExistingGroup(groupId);
        return _chatConfigs[groupId].postingAllowed;
    }

    function scopeSource(uint256 groupId) external view returns (address) {
        _requireExistingGroup(groupId);
        return _chatConfigs[groupId].scopeSource;
    }

    function banSource(uint256 groupId) external view returns (address) {
        _requireExistingGroup(groupId);
        return _chatConfigs[groupId].banSource;
    }

    function beforePostPlugin(uint256 groupId) external view returns (address) {
        _requireExistingGroup(groupId);
        return _chatConfigs[groupId].beforePostPlugin;
    }

    function afterPostPlugin(uint256 groupId) external view returns (address) {
        _requireExistingGroup(groupId);
        return _chatConfigs[groupId].afterPostPlugin;
    }

    function canPost(uint256 groupId, uint256 senderId)
        external
        view
        returns (bool allowed, PostRejectionReason reason)
    {
        return _canPost(groupId, senderId);
    }

    function currentRound() public view returns (uint256) {
        uint256 round = IPhase(PHASE_ADDRESS).currentPhase();
        if (round == 0) {
            revert RoundNotStarted(1, 0);
        }
        return round;
    }

    function messagesCount(uint256 groupId) external view returns (uint256) {
        _requireExistingGroup(groupId);
        return _messagesByChat[groupId].length;
    }

    function message(uint256 groupId, uint256 messageId) external view returns (Message memory) {
        _requireExistingGroup(groupId);
        if (messageId == 0 || messageId > _messagesByChat[groupId].length) {
            revert MessageNotFound(groupId, messageId);
        }
        uint256 messageIndex = messageId - 1;
        return _copyMessage(_messagesByChat[groupId][messageIndex], groupId, messageIndex);
    }

    function messagesByRoundCount(uint256 groupId, uint256 round) external view returns (uint256) {
        _requireExistingGroup(groupId);
        RoundState storage state = _roundStates[groupId][round];
        if (state.startIndexPlusOne == 0) {
            return 0;
        }
        uint256 startIndex = state.startIndexPlusOne - 1;
        return state.endIndex - startIndex + 1;
    }

    function messagesBySenderCount(uint256 groupId, uint256 senderId) external view returns (uint256) {
        _requireExistingGroup(groupId);
        return _senderMessageIndexes[groupId][senderId].length;
    }

    function senderIdsCount(uint256 groupId) external view returns (uint256) {
        _requireExistingGroup(groupId);
        return _senderIdsByChat[groupId].length;
    }

    function groupIdsCount() external view returns (uint256) {
        return _groupIds.length;
    }

    function messages(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory)
    {
        _requireExistingGroup(groupId);
        return _messagesPage(groupId, 0, _messagesByChat[groupId].length, offset, limit, reverse);
    }

    function messagesByRound(uint256 groupId, uint256 round, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory)
    {
        _requireExistingGroup(groupId);
        RoundState storage state = _roundStates[groupId][round];
        if (state.startIndexPlusOne == 0) {
            return new Message[](0);
        }

        uint256 startIndex = state.startIndexPlusOne - 1;
        uint256 total = state.endIndex - startIndex + 1;
        return _messagesPage(groupId, startIndex, total, offset, limit, reverse);
    }

    function messagesBySender(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory)
    {
        _requireExistingGroup(groupId);
        return _messagesByIndexes(groupId, _senderMessageIndexes[groupId][senderId], offset, limit, reverse);
    }

    function messageIdsBySender(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory)
    {
        _requireExistingGroup(groupId);
        return _messageIdsByIndexes(_senderMessageIndexes[groupId][senderId], offset, limit, reverse);
    }

    function messagesByMentionCount(uint256 groupId, uint256 mentionedSenderId) external view returns (uint256) {
        _requireExistingGroup(groupId);
        return _mentionMessageIndexes[groupId][mentionedSenderId].length;
    }

    function messagesByMention(uint256 groupId, uint256 mentionedSenderId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory)
    {
        _requireExistingGroup(groupId);
        return _messagesByIndexes(groupId, _mentionMessageIndexes[groupId][mentionedSenderId], offset, limit, reverse);
    }

    function messageIdsByMention(
        uint256 groupId,
        uint256 mentionedSenderId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) external view returns (uint256[] memory) {
        _requireExistingGroup(groupId);
        return _messageIdsByIndexes(_mentionMessageIndexes[groupId][mentionedSenderId], offset, limit, reverse);
    }

    function messagesByMentionAllCount(uint256 groupId) external view returns (uint256) {
        _requireExistingGroup(groupId);
        return _mentionAllMessageIndexes[groupId].length;
    }

    function messagesByMentionAll(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory)
    {
        _requireExistingGroup(groupId);
        return _messagesByIndexes(groupId, _mentionAllMessageIndexes[groupId], offset, limit, reverse);
    }

    function messageIdsByMentionAll(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory)
    {
        _requireExistingGroup(groupId);
        return _messageIdsByIndexes(_mentionAllMessageIndexes[groupId], offset, limit, reverse);
    }

    function senderIds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory)
    {
        _requireExistingGroup(groupId);
        return _uint256Page(_senderIdsByChat[groupId], offset, limit, reverse);
    }

    function groupIds(uint256 offset, uint256 limit, bool reverse) external view returns (uint256[] memory) {
        return _uint256Page(_groupIds, offset, limit, reverse);
    }

    function roundsCount(uint256 groupId) external view returns (uint256) {
        _requireExistingGroup(groupId);
        return _roundListByChat[groupId].length;
    }

    function rounds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (RoundSpan[] memory)
    {
        _requireExistingGroup(groupId);
        uint256[] storage list = _roundListByChat[groupId];
        uint256 count = Pagination.pageCount(list.length, offset, limit);
        RoundSpan[] memory result = new RoundSpan[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 round = list[Pagination.pageIndex(list.length, offset, i, reverse)];
            result[i] = _roundSpan(groupId, round);
        }

        return result;
    }

    function roundInfo(uint256 groupId, uint256 round) external view returns (RoundSpan memory) {
        _requireExistingGroup(groupId);
        return _roundSpanOrEmpty(groupId, round);
    }

    function roundInfos(uint256 groupId, uint256[] calldata rounds_) external view returns (RoundSpan[] memory) {
        _requireExistingGroup(groupId);
        RoundSpan[] memory result = new RoundSpan[](rounds_.length);

        for (uint256 i = 0; i < rounds_.length; i++) {
            result[i] = _roundSpanOrEmpty(groupId, rounds_[i]);
        }

        return result;
    }

    function _setSource(
        uint256 groupId,
        uint256 operatorId,
        address sourceAddress,
        bool isScope
    ) internal {
        _requireActivated(groupId);
        _validateSourceAddress(sourceAddress);

        ChatConfig storage config = _chatConfigs[groupId];
        address prevSourceAddress = isScope ? config.scopeSource : config.banSource;
        if (prevSourceAddress == sourceAddress) {
            return;
        }

        if (isScope) {
            // forge-lint: disable-next-item(missing-events-access-control)
            config.scopeSource = sourceAddress;
        } else {
            config.banSource = sourceAddress;
        }

        if (isScope) {
            emit SetScopeSource(groupId, sourceAddress, operatorId, msg.sender, prevSourceAddress);
        } else {
            emit SetBanSource(groupId, sourceAddress, operatorId, msg.sender, prevSourceAddress);
        }
    }

    function _setPostPlugin(
        uint256 groupId,
        uint256 operatorId,
        address pluginAddress,
        bool isBefore
    ) internal {
        _requireActivated(groupId);
        _validatePluginAddress(pluginAddress);

        ChatConfig storage config = _chatConfigs[groupId];
        address prevPluginAddress = isBefore ? config.beforePostPlugin : config.afterPostPlugin;
        if (prevPluginAddress == pluginAddress) {
            return;
        }

        if (isBefore) {
            // forge-lint: disable-next-item(missing-events-access-control)
            config.beforePostPlugin = pluginAddress;
        } else {
            config.afterPostPlugin = pluginAddress;
        }

        if (isBefore) {
            emit SetBeforePostPlugin(groupId, pluginAddress, operatorId, msg.sender, prevPluginAddress);
        } else {
            emit SetAfterPostPlugin(groupId, pluginAddress, operatorId, msg.sender, prevPluginAddress);
        }
    }

    function _recordRound(uint256 groupId, uint256 round, uint256 messageIndex) internal {
        RoundState storage state = _roundStates[groupId][round];
        if (state.startIndexPlusOne == 0) {
            state.startIndexPlusOne = messageIndex + 1;
            state.endIndex = messageIndex;
            _roundListByChat[groupId].push(round);
            return;
        }

        state.endIndex = messageIndex;
    }

    function _uint256Page(uint256[] storage source, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 count = Pagination.pageCount(source.length, offset, limit);
        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = source[Pagination.pageIndex(source.length, offset, i, reverse)];
        }

        return result;
    }

    function _messagesPage(
        uint256 groupId,
        uint256 startIndex,
        uint256 total,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (Message[] memory) {
        uint256 count = Pagination.pageCount(total, offset, limit);
        Message[] memory result = new Message[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 messageIndex = startIndex + Pagination.pageIndex(total, offset, i, reverse);
            result[i] = _copyMessage(_messagesByChat[groupId][messageIndex], groupId, messageIndex);
        }

        return result;
    }

    function _messagesByIndexes(uint256 groupId, uint256[] storage indexes, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (Message[] memory)
    {
        uint256 count = Pagination.pageCount(indexes.length, offset, limit);
        Message[] memory result = new Message[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 messageIndex = indexes[Pagination.pageIndex(indexes.length, offset, i, reverse)];
            result[i] = _copyMessage(_messagesByChat[groupId][messageIndex], groupId, messageIndex);
        }

        return result;
    }

    function _messageIdsByIndexes(uint256[] storage indexes, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 count = Pagination.pageCount(indexes.length, offset, limit);
        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = indexes[Pagination.pageIndex(indexes.length, offset, i, reverse)] + 1;
        }

        return result;
    }

    modifier onlyOwnerOrDelegate(
        uint256 groupId,
        uint256 operatorId
    ) {
        uint256 resolvedOperatorId =
            IGroupChatDelegate(GROUP_DELEGATE_ADDRESS).ownerOrDelegateIdOf(groupId, msg.sender);
        if (resolvedOperatorId == 0 || resolvedOperatorId != operatorId) {
            revert NotGroupOperator(groupId, operatorId);
        }
        _;
    }

    function _requireActivated(uint256 groupId) internal view {
        _ownerOfOrRevertGroupNotExist(groupId);
        if (!_chatConfigs[groupId].activated) {
            revert ChatNotActivated(groupId);
        }
    }

    function _requireMentionAllOperator(uint256 groupId, uint256 senderId, uint256 delegateId) internal view {
        if (senderId == groupId || delegateId == senderId) {
            return;
        }
        if (IGroupAdmin(GROUP_ADMIN_ADDRESS).isAdminId(groupId, senderId)) {
            return;
        }
        revert MentionAllUnauthorized(groupId, senderId);
    }

    function _requirePostSources(ChatConfig storage config, uint256 groupId, uint256 senderId, uint256 delegateId)
        internal
        view
    {
        PostRejectionReason reason = _postSourceRejection(config, groupId, senderId, delegateId);
        if (reason != PostRejectionReason.None) {
            _revertPostSourceReason(config, reason, groupId, senderId);
        }
    }

    function _postSourceRejection(ChatConfig storage config, uint256 groupId, uint256 senderId, uint256 delegateId)
        internal
        view
        returns (PostRejectionReason reason)
    {
        if (senderId == groupId || delegateId == senderId) {
            return PostRejectionReason.None;
        }
        if (config.scopeSource != address(0)) {
            try IPostScopeSource(config.scopeSource).canPost(groupId, senderId) returns (bool sourceAllowed) {
                if (!sourceAllowed) {
                    return PostRejectionReason.ScopeRejected;
                }
            } catch {
                return PostRejectionReason.ScopeSourceFailed;
            }
        }
        if (config.banSource != address(0)) {
            try IPostBanSource(config.banSource).isBanned(groupId, senderId) returns (bool banned) {
                if (banned) {
                    return PostRejectionReason.BanRejected;
                }
            } catch {
                return PostRejectionReason.BanSourceFailed;
            }
        }
        return PostRejectionReason.None;
    }

    function _revertPostSourceReason(
        ChatConfig storage config,
        PostRejectionReason reason,
        uint256 groupId,
        uint256 senderId
    ) internal view {
        if (reason == PostRejectionReason.ScopeRejected) {
            revert ScopeRejected(config.scopeSource, groupId, senderId);
        }
        if (reason == PostRejectionReason.BanRejected) {
            revert BanRejected(config.banSource, groupId, senderId);
        }
        if (reason == PostRejectionReason.ScopeSourceFailed) {
            revert ScopeSourceFailed(config.scopeSource);
        }
        if (reason == PostRejectionReason.BanSourceFailed) {
            revert BanSourceFailed(config.banSource);
        }
        assert(false);
    }

    function _canPost(uint256 groupId, uint256 senderId)
        internal
        view
        returns (bool allowed, PostRejectionReason reason)
    {
        if (MemberOwner.ofOrZero(GROUP_ADDRESS, groupId) == address(0)) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, PostRejectionReason.GroupNotExist);
        }

        ChatConfig storage config = _chatConfigs[groupId];
        if (!config.activated) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, PostRejectionReason.ChatNotActivated);
        }
        if (!config.postingAllowed) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, PostRejectionReason.PostingNotAllowed);
        }

        if (MemberOwner.ofOrZero(GROUP_ADDRESS, senderId) == address(0)) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, PostRejectionReason.SenderNotExist);
        }

        reason = _postSourceRejection(
            config, groupId, senderId, IGroupChatDelegate(GROUP_DELEGATE_ADDRESS).delegateIdOf(groupId)
        );
        if (reason != PostRejectionReason.None) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, reason);
        }

        // forge-lint: disable-next-item(boolean-cst)
        return (true, PostRejectionReason.None);
    }

    function _requireExistingGroup(uint256 groupId) internal view {
        _ownerOfOrRevertGroupNotExist(groupId);
    }

    function _ownerOfOrRevertGroupNotExist(uint256 groupId) internal view returns (address owner) {
        owner = MemberOwner.ofOrZero(GROUP_ADDRESS, groupId);
        if (owner == address(0)) {
            revert GroupNotExist(groupId);
        }
    }

    function _validateSourceAddress(address sourceAddress) internal view {
        if (sourceAddress != address(0) && sourceAddress.code.length == 0) {
            revert SourceNotContract(sourceAddress);
        }
    }

    function _validatePluginAddress(address pluginAddress) internal view {
        if (pluginAddress != address(0) && pluginAddress.code.length == 0) {
            revert PluginNotContract(pluginAddress);
        }
    }

    function _validateMentionedSenderIds(uint256[] calldata mentionedSenderIds) internal view {
        if (mentionedSenderIds.length == 0) {
            return;
        }
        if (mentionedSenderIds.length > MAX_MENTIONED_SENDER_IDS) {
            revert TooManyMentionedSenderIds(mentionedSenderIds.length, MAX_MENTIONED_SENDER_IDS);
        }
        for (uint256 i = 0; i < mentionedSenderIds.length; i++) {
            uint256 mentionedSenderId = mentionedSenderIds[i];
            MemberOwner.ownerOf(GROUP_ADDRESS, mentionedSenderId);
            for (uint256 j = 0; j < i; j++) {
                if (mentionedSenderIds[j] == mentionedSenderId) {
                    revert DuplicateMemberId(mentionedSenderId);
                }
            }
        }
    }

    function _storeMessage(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId,
        uint256 round
    ) internal returns (uint256 messageIndex) {
        messageIndex = _messagesByChat[groupId].length;
        _messagesByChat[groupId].push();

        StoredMessage storage message_ = _messagesByChat[groupId][messageIndex];
        message_.senderId = senderId;
        message_.senderAddress = msg.sender;
        message_.content = content;
        message_.blockNumber = block.number;
        message_.timestamp = block.timestamp;
        message_.round = round;
        message_.mentionAll = mentionAll;
        message_.quotedMessageId = quotedMessageId;

        for (uint256 i = 0; i < mentionedSenderIds.length; i++) {
            uint256 mentionedSenderId = mentionedSenderIds[i];
            message_.mentionedSenderIds.push(mentionedSenderId);
            _mentionMessageIndexes[groupId][mentionedSenderId].push(messageIndex);
        }
        if (mentionAll) {
            _mentionAllMessageIndexes[groupId].push(messageIndex);
        }
    }

    function _roundSpan(uint256 groupId, uint256 round) internal view returns (RoundSpan memory) {
        RoundState storage state = _roundStates[groupId][round];
        uint256 startIndex = state.startIndexPlusOne - 1;
        return RoundSpan({
            round: round,
            startMessageId: state.startIndexPlusOne,
            endMessageId: state.endIndex + 1,
            messageCount: state.endIndex - startIndex + 1
        });
    }

    function _roundSpanOrEmpty(uint256 groupId, uint256 round) internal view returns (RoundSpan memory) {
        RoundState storage state = _roundStates[groupId][round];
        if (state.startIndexPlusOne == 0) {
            return RoundSpan(round, 0, 0, 0);
        }
        return _roundSpan(groupId, round);
    }

    function _copyMessage(StoredMessage storage source, uint256 groupId, uint256 messageIndex)
        internal
        view
        returns (Message memory result)
    {
        result.groupId = groupId;
        result.senderId = source.senderId;
        result.senderAddress = source.senderAddress;
        result.round = source.round;
        result.messageId = messageIndex + 1;
        result.content = source.content;
        result.blockNumber = source.blockNumber;
        result.timestamp = source.timestamp;
        result.mentionAll = source.mentionAll;
        result.quotedMessageId = source.quotedMessageId;
        result.mentionedSenderIds = new uint256[](source.mentionedSenderIds.length);

        for (uint256 i = 0; i < source.mentionedSenderIds.length; i++) {
            result.mentionedSenderIds[i] = source.mentionedSenderIds[i];
        }
    }

    function _validateQuotedMessageId(uint256 groupId, uint256 quotedMessageId) internal view {
        if (quotedMessageId == 0) {
            return;
        }
        if (quotedMessageId > _messagesByChat[groupId].length) {
            revert QuotedMessageNotFound(groupId, quotedMessageId);
        }
    }
}
