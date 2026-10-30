// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChat} from "./interfaces/IGroupChat.sol";
import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";
import {IGroupChatDelegate} from "./interfaces/IGroupChatDelegate.sol";
import {IAfterPostPlugin} from "./interfaces/plugins/IAfterPostPlugin.sol";
import {IBeforePostPlugin} from "./interfaces/plugins/IBeforePostPlugin.sol";
import {IPostBanSource} from "./interfaces/sources/IPostBanSource.sol";
import {IPostScopeSource} from "./interfaces/sources/IPostScopeSource.sol";
import {MemberOwner} from "@action/MemberOwner.sol";
import {IMemberNFT} from "@core/interfaces/IMemberNFT.sol";
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

    struct MessageRecord {
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

    // groupId => chat config
    mapping(uint256 => ChatConfig) internal _chatConfig;
    // groupId => messages, append-only so messageId is index + 1
    mapping(uint256 => MessageRecord[]) internal _messagesByGroupId;
    // groupId => senderId => message indexes, in posting order
    mapping(uint256 => mapping(uint256 => uint256[])) internal _messageIndexesByGroupIdBySenderId;
    // groupId => mentionedSenderId => message indexes, in posting order
    mapping(uint256 => mapping(uint256 => uint256[])) internal _messageIndexesByGroupIdByMentionedSenderId;
    // groupId => message indexes posted with mentionAll
    mapping(uint256 => uint256[]) internal _mentionAllMessageIndexesByGroupId;
    // groupId => senderIds that posted at least once, in first-post order
    mapping(uint256 => uint256[]) internal _senderIdsByGroupId;
    // groupId => round => span of messages in that round
    mapping(uint256 => mapping(uint256 => RoundState)) internal _roundStateByGroupIdByRound;
    // groupId => rounds that have at least one message, in first-message order
    mapping(uint256 => uint256[]) internal _roundsByGroupId;
    // all activated groupIds, in activation order
    uint256[] internal _groupIds;

    uint256 internal _reentrancyStatus;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(
        address groupAdminAddress,
        address phaseAddress,
        uint256 maxContentLength,
        uint256 maxMentionedSenderIds
    ) {
        address groupDelegateAddress = IGroupAdmin(groupAdminAddress).GROUP_DELEGATE_ADDRESS();
        address groupAddress = IGroupAdmin(groupAdminAddress).GROUP_ADDRESS();
        GROUP_ADMIN_ADDRESS = groupAdminAddress;
        GROUP_DELEGATE_ADDRESS = groupDelegateAddress;
        GROUP_ADDRESS = groupAddress;
        PHASE_ADDRESS = phaseAddress;
        MAX_CONTENT_LENGTH = maxContentLength;
        MAX_MENTIONED_SENDER_IDS = maxMentionedSenderIds;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus != 0) {
            revert Reentrant();
        }
        _reentrancyStatus = 1;
        _;
        _reentrancyStatus = 0;
    }

    modifier onlySenderOwner(uint256 senderId) {
        if (IMemberNFT(GROUP_ADDRESS).ownerOf(senderId) != msg.sender) {
            revert NotMemberOwner(senderId);
        }
        _;
    }

    modifier onlyChatOwner(uint256 groupId) {
        if (msg.sender != _ownerOrRevertGroupNotExist(groupId)) {
            revert NotGroupOwner(groupId);
        }
        _;
    }

    function activateChat(
        uint256 groupId,
        address scopeSourceAddress,
        address banSourceAddress,
        address beforePostPluginAddress,
        address afterPostPluginAddress
    ) external nonReentrant onlyChatOwner(groupId) {
        address owner = _ownerOrRevertGroupNotExist(groupId);

        ChatConfig storage config = _chatConfig[groupId];
        if (config.activated) {
            revert ChatAlreadyActivated(groupId);
        }

        _validateSourceAddress(scopeSourceAddress);
        _validateSourceAddress(banSourceAddress);
        _validatePluginAddress(beforePostPluginAddress);
        _validatePluginAddress(afterPostPluginAddress);

        config.firstActivatedOwner = owner;
        config.firstActivatedBlockNumber = block.number;
        config.firstActivatedTimestamp = block.timestamp;
        _groupIds.push(groupId);

        config.activated = true;
        config.postingAllowed = true;
        config.scopeSource = scopeSourceAddress;
        config.banSource = banSourceAddress;
        config.beforePostPlugin = beforePostPluginAddress;
        config.afterPostPlugin = afterPostPluginAddress;

        emit GroupChatActivated({
            groupId: groupId,
            ownerId: groupId,
            owner: owner,
            postingAllowed: config.postingAllowed,
            scopeSource: scopeSourceAddress,
            banSource: banSourceAddress,
            beforePostPlugin: beforePostPluginAddress,
            afterPostPlugin: afterPostPluginAddress
        });
    }

    function setPostingAllowed(uint256 groupId, uint256 operatorId, bool postingAllowed)
        external
        nonReentrant
        onlyOwnerOrDelegate(groupId, operatorId)
    {
        _requireActivated(groupId);

        ChatConfig storage config = _chatConfig[groupId];
        if (config.postingAllowed == postingAllowed) {
            return;
        }

        // forge-lint: disable-next-item(missing-events-access-control)
        config.postingAllowed = postingAllowed;
        emit PostingAllowedChanged({
            groupId: groupId,
            operatorId: operatorId,
            operator: msg.sender,
            postingAllowed: postingAllowed
        });
    }

    function setScopeSource(
        uint256 groupId,
        uint256 operatorId,
        address scopeSourceAddress
    ) external nonReentrant onlyOwnerOrDelegate(groupId, operatorId) {
        _setSource(groupId, operatorId, scopeSourceAddress, true);
    }

    function setBanSource(
        uint256 groupId,
        uint256 operatorId,
        address banSourceAddress
    ) external nonReentrant onlyOwnerOrDelegate(groupId, operatorId) {
        _setSource(groupId, operatorId, banSourceAddress, false);
    }

    function setBeforePostPlugin(
        uint256 groupId,
        uint256 operatorId,
        address beforePostPluginAddress
    ) external nonReentrant onlyOwnerOrDelegate(groupId, operatorId) {
        _setPostPlugin(groupId, operatorId, beforePostPluginAddress, true);
    }

    function setAfterPostPlugin(
        uint256 groupId,
        uint256 operatorId,
        address afterPostPluginAddress
    ) external nonReentrant onlyOwnerOrDelegate(groupId, operatorId) {
        _setPostPlugin(groupId, operatorId, afterPostPluginAddress, false);
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
        ChatConfig storage config = _chatConfig[groupId];
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
        uint256 delegateId = IGroupChatDelegate(GROUP_DELEGATE_ADDRESS).effectiveDelegateId(groupId);
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

        if (_messageIndexesByGroupIdBySenderId[groupId][senderId].length == 0) {
            _senderIdsByGroupId[groupId].push(senderId);
        }
        _messageIndexesByGroupIdBySenderId[groupId][senderId].push(messageIndex);

        _recordRound(groupId, round, messageIndex);

        _emitMessagePosted(groupId, messageIndex);
        for (uint256 i = 0; i < mentionedSenderIds.length; i++) {
            emit SenderMentioned({
                groupId: groupId,
                messageId: messageIndex + 1,
                mentionedSenderId: mentionedSenderIds[i]
            });
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
                emit AfterPostPluginFailed({
                    groupId: groupId,
                    messageId: messageIndex + 1,
                    round: round,
                    pluginAddress: config.afterPostPlugin,
                    errorHash: keccak256(err),
                    errorLength: err.length,
                    errorSelector: errorSelector
                });
            }
        }
    }

    function chatInfo(uint256 groupId) external view returns (ChatInfo memory info) {
        return _chatInfo(groupId);
    }

    function chatInfosByGroupIds(uint256[] calldata requestedGroupIds) external view returns (ChatInfo[] memory) {
        ChatInfo[] memory result = new ChatInfo[](requestedGroupIds.length);

        for (uint256 i = 0; i < requestedGroupIds.length; i++) {
            result[i] = _chatInfo(requestedGroupIds[i]);
        }

        return result;
    }

    function _chatInfo(uint256 groupId) internal view returns (ChatInfo memory) {
        address owner = _ownerOrRevertGroupNotExist(groupId);
        ChatConfig storage config = _chatConfig[groupId];
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

    function isPostingAllowed(uint256 groupId) external view returns (bool) {
        _requireExistingGroup(groupId);
        return _chatConfig[groupId].postingAllowed;
    }

    function scopeSource(uint256 groupId) external view returns (address) {
        _requireExistingGroup(groupId);
        return _chatConfig[groupId].scopeSource;
    }

    function banSource(uint256 groupId) external view returns (address) {
        _requireExistingGroup(groupId);
        return _chatConfig[groupId].banSource;
    }

    function beforePostPlugin(uint256 groupId) external view returns (address) {
        _requireExistingGroup(groupId);
        return _chatConfig[groupId].beforePostPlugin;
    }

    function afterPostPlugin(uint256 groupId) external view returns (address) {
        _requireExistingGroup(groupId);
        return _chatConfig[groupId].afterPostPlugin;
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

    function message(uint256 groupId, uint256 messageId) external view returns (Message memory storedMessage) {
        _requireExistingGroup(groupId);
        if (messageId == 0 || messageId > _messagesByGroupId[groupId].length) {
            revert MessageNotFound(groupId, messageId);
        }
        uint256 messageIndex = messageId - 1;
        return _copyMessage(_messagesByGroupId[groupId][messageIndex], groupId, messageIndex);
    }

    function messages(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory messageList, uint256 totalCount)
    {
        _requireExistingGroup(groupId);
        totalCount = _messagesByGroupId[groupId].length;
        messageList = _messagesPage(groupId, 0, totalCount, offset, limit, reverse);
    }

    function messagesByRound(uint256 groupId, uint256 round, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory messageList, uint256 totalCount)
    {
        _requireExistingGroup(groupId);
        RoundState storage state = _roundStateByGroupIdByRound[groupId][round];
        if (state.startIndexPlusOne == 0) {
            return (new Message[](0), 0);
        }

        uint256 startIndex = state.startIndexPlusOne - 1;
        totalCount = state.endIndex - startIndex + 1;
        messageList = _messagesPage(groupId, startIndex, totalCount, offset, limit, reverse);
    }

    function messagesBySenderId(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory messageList, uint256 totalCount)
    {
        _requireExistingGroup(groupId);
        uint256[] storage indexes = _messageIndexesByGroupIdBySenderId[groupId][senderId];
        totalCount = indexes.length;
        messageList = _messagesByIndexes(groupId, indexes, offset, limit, reverse);
    }

    function messageIdsBySenderId(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory messageIds, uint256 totalCount)
    {
        _requireExistingGroup(groupId);
        uint256[] storage indexes = _messageIndexesByGroupIdBySenderId[groupId][senderId];
        totalCount = indexes.length;
        messageIds = _messageIdsByIndexes(indexes, offset, limit, reverse);
    }

    function messagesByMentionedSenderId(
        uint256 groupId,
        uint256 mentionedSenderId,
        uint256 offset,
        uint256 limit,
        bool reverse
    )
        external
        view
        returns (Message[] memory messageList, uint256 totalCount)
    {
        _requireExistingGroup(groupId);
        uint256[] storage indexes = _messageIndexesByGroupIdByMentionedSenderId[groupId][mentionedSenderId];
        totalCount = indexes.length;
        messageList = _messagesByIndexes(groupId, indexes, offset, limit, reverse);
    }

    function messageIdsByMentionedSenderId(
        uint256 groupId,
        uint256 mentionedSenderId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) external view returns (uint256[] memory messageIds, uint256 totalCount) {
        _requireExistingGroup(groupId);
        uint256[] storage indexes = _messageIndexesByGroupIdByMentionedSenderId[groupId][mentionedSenderId];
        totalCount = indexes.length;
        messageIds = _messageIdsByIndexes(indexes, offset, limit, reverse);
    }

    function mentionAllMessages(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory messageList, uint256 totalCount)
    {
        _requireExistingGroup(groupId);
        uint256[] storage indexes = _mentionAllMessageIndexesByGroupId[groupId];
        totalCount = indexes.length;
        messageList = _messagesByIndexes(groupId, indexes, offset, limit, reverse);
    }

    function mentionAllMessageIds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory messageIds, uint256 totalCount)
    {
        _requireExistingGroup(groupId);
        uint256[] storage indexes = _mentionAllMessageIndexesByGroupId[groupId];
        totalCount = indexes.length;
        messageIds = _messageIdsByIndexes(indexes, offset, limit, reverse);
    }

    function senderIds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory senderIdList, uint256 totalCount)
    {
        _requireExistingGroup(groupId);
        uint256[] storage list = _senderIdsByGroupId[groupId];
        totalCount = list.length;
        senderIdList = _uint256Page(list, offset, limit, reverse);
    }

    function groupIds(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory groupIdList, uint256 totalCount)
    {
        totalCount = _groupIds.length;
        groupIdList = _uint256Page(_groupIds, offset, limit, reverse);
    }

    function rounds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (RoundSpan[] memory roundList, uint256 totalCount)
    {
        _requireExistingGroup(groupId);
        uint256[] storage list = _roundsByGroupId[groupId];
        totalCount = list.length;
        uint256 count = Pagination.pageCount(totalCount, offset, limit);
        roundList = new RoundSpan[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 round = list[Pagination.pageIndex(totalCount, offset, i, reverse)];
            roundList[i] = _roundSpan(groupId, round);
        }
    }

    function roundInfo(uint256 groupId, uint256 round) external view returns (RoundSpan memory roundSpan) {
        _requireExistingGroup(groupId);
        return _roundSpanOrEmpty(groupId, round);
    }

    function roundInfosByRounds(uint256 groupId, uint256[] calldata requestedRounds)
        external
        view
        returns (RoundSpan[] memory)
    {
        _requireExistingGroup(groupId);
        RoundSpan[] memory result = new RoundSpan[](requestedRounds.length);

        for (uint256 i = 0; i < requestedRounds.length; i++) {
            result[i] = _roundSpanOrEmpty(groupId, requestedRounds[i]);
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

        ChatConfig storage config = _chatConfig[groupId];
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
            emit ScopeSourceChanged({
                groupId: groupId,
                sourceAddress: sourceAddress,
                operatorId: operatorId,
                operator: msg.sender,
                prevSourceAddress: prevSourceAddress
            });
        } else {
            emit BanSourceChanged({
                groupId: groupId,
                sourceAddress: sourceAddress,
                operatorId: operatorId,
                operator: msg.sender,
                prevSourceAddress: prevSourceAddress
            });
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

        ChatConfig storage config = _chatConfig[groupId];
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
            emit BeforePostPluginChanged({
                groupId: groupId,
                pluginAddress: pluginAddress,
                operatorId: operatorId,
                operator: msg.sender,
                prevPluginAddress: prevPluginAddress
            });
        } else {
            emit AfterPostPluginChanged({
                groupId: groupId,
                pluginAddress: pluginAddress,
                operatorId: operatorId,
                operator: msg.sender,
                prevPluginAddress: prevPluginAddress
            });
        }
    }

    function _recordRound(uint256 groupId, uint256 round, uint256 messageIndex) internal {
        RoundState storage state = _roundStateByGroupIdByRound[groupId][round];
        if (state.startIndexPlusOne == 0) {
            state.startIndexPlusOne = messageIndex + 1;
            state.endIndex = messageIndex;
            _roundsByGroupId[groupId].push(round);
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
            result[i] = _copyMessage(_messagesByGroupId[groupId][messageIndex], groupId, messageIndex);
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
            result[i] = _copyMessage(_messagesByGroupId[groupId][messageIndex], groupId, messageIndex);
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
            IGroupChatDelegate(GROUP_DELEGATE_ADDRESS).ownerOrDelegateId(groupId, msg.sender);
        if (resolvedOperatorId == 0 || resolvedOperatorId != operatorId) {
            revert NotGroupOperator(groupId, operatorId);
        }
        _;
    }

    function _requireActivated(uint256 groupId) internal view {
        _ownerOrRevertGroupNotExist(groupId);
        if (!_chatConfig[groupId].activated) {
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
            try IPostScopeSource(config.scopeSource).isSenderAllowed(groupId, senderId) returns (bool sourceAllowed) {
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
            revert ScopeRejected(groupId, senderId, config.scopeSource);
        }
        if (reason == PostRejectionReason.BanRejected) {
            revert BanRejected(groupId, senderId, config.banSource);
        }
        if (reason == PostRejectionReason.ScopeSourceFailed) {
            revert ScopeSourceFailed(groupId, config.scopeSource);
        }
        if (reason == PostRejectionReason.BanSourceFailed) {
            revert BanSourceFailed(groupId, config.banSource);
        }
        assert(false);
    }

    function _canPost(uint256 groupId, uint256 senderId)
        internal
        view
        returns (bool allowed, PostRejectionReason reason)
    {
        if (MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId) == address(0)) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, PostRejectionReason.GroupNotExist);
        }

        ChatConfig storage config = _chatConfig[groupId];
        if (!config.activated) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, PostRejectionReason.ChatNotActivated);
        }
        if (!config.postingAllowed) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, PostRejectionReason.PostingNotAllowed);
        }

        if (MemberOwner.ownerOrZero(GROUP_ADDRESS, senderId) == address(0)) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, PostRejectionReason.SenderNotExist);
        }

        reason = _postSourceRejection(
            config, groupId, senderId, IGroupChatDelegate(GROUP_DELEGATE_ADDRESS).effectiveDelegateId(groupId)
        );
        if (reason != PostRejectionReason.None) {
            // forge-lint: disable-next-item(boolean-cst)
            return (false, reason);
        }

        // forge-lint: disable-next-item(boolean-cst)
        return (true, PostRejectionReason.None);
    }

    function _requireExistingGroup(uint256 groupId) internal view {
        _ownerOrRevertGroupNotExist(groupId);
    }

    function _ownerOrRevertGroupNotExist(uint256 groupId) internal view returns (address owner) {
        owner = MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId);
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
            IMemberNFT(GROUP_ADDRESS).ownerOf(mentionedSenderId);
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
        messageIndex = _messagesByGroupId[groupId].length;
        _messagesByGroupId[groupId].push();

        MessageRecord storage storedMessage = _messagesByGroupId[groupId][messageIndex];
        storedMessage.senderId = senderId;
        storedMessage.senderAddress = msg.sender;
        storedMessage.content = content;
        storedMessage.blockNumber = block.number;
        storedMessage.timestamp = block.timestamp;
        storedMessage.round = round;
        storedMessage.mentionAll = mentionAll;
        storedMessage.quotedMessageId = quotedMessageId;

        for (uint256 i = 0; i < mentionedSenderIds.length; i++) {
            uint256 mentionedSenderId = mentionedSenderIds[i];
            storedMessage.mentionedSenderIds.push(mentionedSenderId);
            _messageIndexesByGroupIdByMentionedSenderId[groupId][mentionedSenderId].push(messageIndex);
        }
        if (mentionAll) {
            _mentionAllMessageIndexesByGroupId[groupId].push(messageIndex);
        }
    }

    function _roundSpan(uint256 groupId, uint256 round) internal view returns (RoundSpan memory) {
        RoundState storage state = _roundStateByGroupIdByRound[groupId][round];
        uint256 startIndex = state.startIndexPlusOne - 1;
        return RoundSpan({
            round: round,
            startMessageId: state.startIndexPlusOne,
            endMessageId: state.endIndex + 1,
            messageCount: state.endIndex - startIndex + 1
        });
    }

    function _roundSpanOrEmpty(uint256 groupId, uint256 round) internal view returns (RoundSpan memory) {
        RoundState storage state = _roundStateByGroupIdByRound[groupId][round];
        if (state.startIndexPlusOne == 0) {
            return RoundSpan(round, 0, 0, 0);
        }
        return _roundSpan(groupId, round);
    }

    function _copyMessage(MessageRecord storage source, uint256 groupId, uint256 messageIndex)
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
        if (quotedMessageId > _messagesByGroupId[groupId].length) {
            revert QuotedMessageNotFound(groupId, quotedMessageId);
        }
    }

    function _emitMessagePosted(
        uint256 groupId,
        uint256 messageIndex
    ) private {
        MessageRecord storage storedMessage = _messagesByGroupId[groupId][messageIndex];
        emit MessagePosted({
            groupId: groupId,
            messageId: messageIndex + 1,
            senderId: storedMessage.senderId,
            sender: storedMessage.senderAddress,
            round: storedMessage.round,
            quotedMessageId: storedMessage.quotedMessageId,
            hasQuote: storedMessage.quotedMessageId != 0,
            mentionAll: storedMessage.mentionAll,
            mentionedSenderCount: storedMessage.mentionedSenderIds.length,
            content: storedMessage.content
        });
    }
}
