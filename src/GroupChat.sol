// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupChat} from "./interfaces/IGroupChat.sol";

import {IGroupAdmin} from "./interfaces/IGroupAdmin.sol";
import {IGroupDefaults} from "./interfaces/external/IGroupDefaults.sol";
import {IGroupDelegate} from "./interfaces/external/IGroupDelegate.sol";
import {ILOVE20Group} from "./interfaces/external/ILOVE20Group.sol";
import {IAfterPostPlugin} from "./interfaces/plugins/IAfterPostPlugin.sol";
import {IBeforePostPlugin} from "./interfaces/plugins/IBeforePostPlugin.sol";
import {IPostBanSource} from "./interfaces/sources/IPostBanSource.sol";
import {IPostScopeSource} from "./interfaces/sources/IPostScopeSource.sol";

contract GroupChat is IGroupChat {
    uint256 public immutable MAX_CONTENT_LENGTH;
    uint256 public immutable MAX_MENTIONED_SENDER_IDS;

    address public immutable GROUP_ADMIN_ADDRESS;
    address public immutable GROUP_ADDRESS;
    address public immutable GROUP_DEFAULTS_ADDRESS;
    address public immutable GROUP_DELEGATE_ADDRESS;
    uint256 public immutable originBlocks;
    uint256 public immutable phaseBlocks;

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

    constructor(
        address groupAdmin_,
        uint256 originBlocks_,
        uint256 phaseBlocks_,
        uint256 maxContentLength_,
        uint256 maxMentionedSenderIds_
    ) {
        if (groupAdmin_.code.length == 0) {
            revert GroupAdminHasNoCode();
        }
        if (phaseBlocks_ == 0) {
            revert PhaseBlocksZero();
        }
        if (maxContentLength_ == 0) {
            revert MaxContentLengthZero();
        }

        address groupDefaults = IGroupAdmin(groupAdmin_).GROUP_DEFAULTS_ADDRESS();
        address groupDelegate = IGroupAdmin(groupAdmin_).GROUP_DELEGATE_ADDRESS();
        address groupAddress = IGroupAdmin(groupAdmin_).GROUP_ADDRESS();
        if (groupDefaults.code.length == 0) {
            revert GroupDefaultsHasNoCode();
        }
        if (groupDelegate.code.length == 0) {
            revert GroupDelegateHasNoCode();
        }
        if (IGroupDefaults(groupDefaults).GROUP_ADDRESS() != groupAddress) {
            revert GroupDefaultsGroupMismatch();
        }
        if (IGroupDelegate(groupDelegate).GROUP_ADDRESS() != groupAddress) {
            revert GroupDelegateGroupMismatch();
        }
        GROUP_ADMIN_ADDRESS = groupAdmin_;
        GROUP_DEFAULTS_ADDRESS = groupDefaults;
        GROUP_DELEGATE_ADDRESS = groupDelegate;
        GROUP_ADDRESS = groupAddress;
        originBlocks = originBlocks_;
        phaseBlocks = phaseBlocks_;
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

    function activateChat(
        uint256 groupId,
        address scopeSource_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_
    ) external nonReentrant {
        address owner = _ownerOfOrRevert(groupId);
        if (msg.sender != owner) {
            revert NotChatOwner();
        }

        ChatConfig storage config = _chatConfigs[groupId];
        if (config.activated) {
            revert ChatAlreadyActivated();
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
            emit SetScopeSource(groupId, scopeSource_, msg.sender, address(0));
        }
        if (banSource_ != address(0)) {
            emit SetBanSource(groupId, banSource_, msg.sender, address(0));
        }
        if (beforePostPlugin_ != address(0)) {
            emit SetBeforePostPlugin(groupId, beforePostPlugin_, msg.sender, address(0));
        }
        if (afterPostPlugin_ != address(0)) {
            emit SetAfterPostPlugin(groupId, afterPostPlugin_, msg.sender, address(0));
        }
        emit Activate(groupId, owner);
    }

    function setPostingAllowed(uint256 groupId, bool postingAllowed_) external nonReentrant {
        _requireOwnerOrDelegateAndActivated(groupId);

        ChatConfig storage config = _chatConfigs[groupId];
        if (config.postingAllowed == postingAllowed_) {
            return;
        }

        config.postingAllowed = postingAllowed_;
        emit SetPostingAllowed(groupId, msg.sender, postingAllowed_);
    }

    function setScopeSource(uint256 groupId, address sourceAddress) external nonReentrant {
        _setSource(groupId, sourceAddress, true);
    }

    function setBanSource(uint256 groupId, address sourceAddress) external nonReentrant {
        _setSource(groupId, sourceAddress, false);
    }

    function setBeforePostPlugin(uint256 groupId, address pluginAddress) external nonReentrant {
        _setPostPlugin(groupId, pluginAddress, true);
    }

    function setAfterPostPlugin(uint256 groupId, address pluginAddress) external nonReentrant {
        _setPostPlugin(groupId, pluginAddress, false);
    }

    function post(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId
    ) external nonReentrant {
        _post(groupId, senderId, content, mentionedSenderIds, mentionAll, quotedMessageId);
    }

    function postAsDefaultSender(
        uint256 groupId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId
    ) external nonReentrant {
        uint256 senderId = IGroupDefaults(GROUP_DEFAULTS_ADDRESS).defaultGroupIdOf(msg.sender);
        if (senderId == 0) {
            revert DefaultGroupIdNotSet();
        }
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
            revert ChatNotActivated();
        }
        if (!config.postingAllowed) {
            revert PostingNotAllowed();
        }

        address senderOwner = _ownerOfOrRevert(senderId);
        if (msg.sender != senderOwner) {
            revert SenderAddressNotSenderIdOwner();
        }

        uint256 contentLength = bytes(content).length;
        if (contentLength == 0) {
            revert ContentEmpty();
        }
        if (contentLength > MAX_CONTENT_LENGTH) {
            revert ContentTooLong(contentLength, MAX_CONTENT_LENGTH);
        }
        _validateMentionedSenderIds(mentionedSenderIds);
        if (mentionAll) {
            _requireMentionAllOperator(groupId);
        }
        _validateQuotedMessageId(groupId, quotedMessageId);

        uint256 round = currentRound();
        _requirePostSources(config, groupId, senderId, msg.sender);
        if (config.beforePostPlugin != address(0)) {
            IBeforePostPlugin(config.beforePostPlugin).beforePost(
                groupId, senderId, msg.sender, content, mentionedSenderIds, mentionAll, quotedMessageId
            );
        }

        uint256 messageIndex =
            _storeMessage(groupId, senderId, content, mentionedSenderIds, mentionAll, quotedMessageId);

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
                emit FailAfterPostPlugin(groupId, messageIndex + 1, config.afterPostPlugin, round, err);
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
        address owner = _ownerOfOrRevert(groupId);
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

    function canPost(uint256 groupId, uint256 senderId, address senderAddress)
        external
        view
        returns (bool allowed, bytes4 reasonCode)
    {
        return _canPost(groupId, senderId, senderAddress);
    }

    function currentRound() public view returns (uint256) {
        if (block.number < originBlocks) {
            revert RoundNotStarted();
        }
        return _roundByBlockNumber(block.number);
    }

    function messagesCount(uint256 groupId) external view returns (uint256) {
        _requireExistingGroup(groupId);
        return _messagesByChat[groupId].length;
    }

    function message(uint256 groupId, uint256 messageId) external view returns (Message memory) {
        _requireExistingGroup(groupId);
        if (messageId == 0 || messageId > _messagesByChat[groupId].length) {
            revert InvalidMessageId();
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
        uint256 count = _pageCount(list.length, offset, limit);
        RoundSpan[] memory result = new RoundSpan[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 round = list[_pageIndex(list.length, offset, i, reverse)];
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

    function _setSource(uint256 groupId, address sourceAddress, bool isScope) internal {
        _requireOwnerOrDelegateAndActivated(groupId);
        _validateSourceAddress(sourceAddress);

        ChatConfig storage config = _chatConfigs[groupId];
        address prevSourceAddress = isScope ? config.scopeSource : config.banSource;
        if (prevSourceAddress == sourceAddress) {
            return;
        }

        if (isScope) {
            config.scopeSource = sourceAddress;
        } else {
            config.banSource = sourceAddress;
        }

        if (isScope) {
            emit SetScopeSource(groupId, sourceAddress, msg.sender, prevSourceAddress);
        } else {
            emit SetBanSource(groupId, sourceAddress, msg.sender, prevSourceAddress);
        }
    }

    function _setPostPlugin(uint256 groupId, address pluginAddress, bool isBefore) internal {
        _requireOwnerOrDelegateAndActivated(groupId);
        _validatePluginAddress(pluginAddress);

        ChatConfig storage config = _chatConfigs[groupId];
        address prevPluginAddress = isBefore ? config.beforePostPlugin : config.afterPostPlugin;
        if (prevPluginAddress == pluginAddress) {
            return;
        }

        if (isBefore) {
            config.beforePostPlugin = pluginAddress;
        } else {
            config.afterPostPlugin = pluginAddress;
        }

        if (isBefore) {
            emit SetBeforePostPlugin(groupId, pluginAddress, msg.sender, prevPluginAddress);
        } else {
            emit SetAfterPostPlugin(groupId, pluginAddress, msg.sender, prevPluginAddress);
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
        uint256 count = _pageCount(source.length, offset, limit);
        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = source[_pageIndex(source.length, offset, i, reverse)];
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
        uint256 count = _pageCount(total, offset, limit);
        Message[] memory result = new Message[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 messageIndex = startIndex + _pageIndex(total, offset, i, reverse);
            result[i] = _copyMessage(_messagesByChat[groupId][messageIndex], groupId, messageIndex);
        }

        return result;
    }

    function _messagesByIndexes(uint256 groupId, uint256[] storage indexes, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (Message[] memory)
    {
        uint256 count = _pageCount(indexes.length, offset, limit);
        Message[] memory result = new Message[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 messageIndex = indexes[_pageIndex(indexes.length, offset, i, reverse)];
            result[i] = _copyMessage(_messagesByChat[groupId][messageIndex], groupId, messageIndex);
        }

        return result;
    }

    function _messageIdsByIndexes(uint256[] storage indexes, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 count = _pageCount(indexes.length, offset, limit);
        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = indexes[_pageIndex(indexes.length, offset, i, reverse)] + 1;
        }

        return result;
    }

    function _requireOwnerOrDelegateAndActivated(uint256 groupId) internal view {
        _ownerOfOrRevert(groupId);
        ChatConfig storage config = _chatConfigs[groupId];
        if (!config.activated) {
            revert ChatNotActivated();
        }
        if (!_isOwnerOrDelegate(groupId, msg.sender)) {
            revert NotChatOwnerOrDelegateIdOwner();
        }
    }

    function _requireMentionAllOperator(uint256 groupId) internal view {
        IGroupAdmin groupAdmin = IGroupAdmin(GROUP_ADMIN_ADDRESS);
        if (groupAdmin.ownerOrDelegateIdOf(groupId, msg.sender) != 0) {
            return;
        }
        if (groupAdmin.adminIdOf(groupId, msg.sender) != 0) {
            return;
        }
        revert MentionAllUnauthorized();
    }

    function _requirePostSources(ChatConfig storage config, uint256 groupId, uint256 senderId, address senderAddress)
        internal
        view
    {
        bytes4 reasonCode = _postSourceRejection(config, groupId, senderId, senderAddress);
        if (reasonCode != bytes4(0)) {
            _revertPostSourceReason(reasonCode);
        }
    }

    function _postSourceRejection(ChatConfig storage config, uint256 groupId, uint256 senderId, address senderAddress)
        internal
        view
        returns (bytes4 reasonCode)
    {
        if (_isOwnerOrDelegate(groupId, senderAddress)) {
            return bytes4(0);
        }
        if (config.scopeSource != address(0)) {
            try IPostScopeSource(config.scopeSource).canPost(groupId, senderId, senderAddress) returns (
                bool sourceAllowed
            ) {
                if (!sourceAllowed) {
                    return ScopeRejected.selector;
                }
            } catch {
                return ScopeSourceFailed.selector;
            }
        }
        if (config.banSource != address(0)) {
            try IPostBanSource(config.banSource).isBanned(groupId, senderId, senderAddress) returns (bool banned) {
                if (banned) {
                    return BanRejected.selector;
                }
            } catch {
                return BanSourceFailed.selector;
            }
        }
        return bytes4(0);
    }

    function _revertPostSourceReason(bytes4 reasonCode) internal pure {
        if (reasonCode == ScopeRejected.selector) {
            revert ScopeRejected();
        }
        if (reasonCode == ScopeSourceFailed.selector) {
            revert ScopeSourceFailed();
        }
        if (reasonCode == BanRejected.selector) {
            revert BanRejected();
        }
        if (reasonCode == BanSourceFailed.selector) {
            revert BanSourceFailed();
        }
        revert();
    }

    function _isOwnerOrDelegate(uint256 groupId, address account) internal view returns (bool) {
        return IGroupDelegate(GROUP_DELEGATE_ADDRESS).ownerOrDelegateIdOf(groupId, account) != 0;
    }

    function _canPost(uint256 groupId, uint256 senderId, address senderAddress)
        internal
        view
        returns (bool allowed, bytes4 reasonCode)
    {
        (bool chatExists,) = _tryOwnerOf(groupId);
        if (!chatExists) {
            return (false, GroupNotExist.selector);
        }

        ChatConfig storage config = _chatConfigs[groupId];
        if (!config.activated) {
            return (false, ChatNotActivated.selector);
        }
        if (!config.postingAllowed) {
            return (false, PostingNotAllowed.selector);
        }

        (bool senderExists, address senderOwner) = _tryOwnerOf(senderId);
        if (!senderExists) {
            return (false, GroupNotExist.selector);
        }
        if (senderAddress != senderOwner) {
            return (false, SenderAddressNotSenderIdOwner.selector);
        }

        bytes4 sourceReasonCode = _postSourceRejection(config, groupId, senderId, senderAddress);
        if (sourceReasonCode != bytes4(0)) {
            return (false, sourceReasonCode);
        }

        return (true, bytes4(0));
    }

    function _requireExistingGroup(uint256 groupId) internal view {
        _ownerOfOrRevert(groupId);
    }

    function _ownerOfOrRevert(uint256 groupId) internal view returns (address owner) {
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return resolved;
        } catch {
            revert GroupNotExist();
        }
    }

    function _tryOwnerOf(uint256 groupId) internal view returns (bool exists, address owner) {
        try ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) returns (address resolved) {
            return (true, resolved);
        } catch {
            return (false, address(0));
        }
    }

    function _validateSourceAddress(address sourceAddress) internal view {
        if (sourceAddress != address(0) && sourceAddress.code.length == 0) {
            revert SourceAddressHasNoCode();
        }
    }

    function _validatePluginAddress(address pluginAddress) internal view {
        if (pluginAddress != address(0) && pluginAddress.code.length == 0) {
            revert PluginAddressHasNoCode();
        }
    }

    function _validateMentionedSenderIds(uint256[] calldata mentionedSenderIds) internal view {
        if (mentionedSenderIds.length > MAX_MENTIONED_SENDER_IDS) {
            revert TooManyMentionedSenderIds(mentionedSenderIds.length, MAX_MENTIONED_SENDER_IDS);
        }
        // LOVE20Group mints token IDs as 1..totalSupply and does not expose an NFT burn path.
        uint256 mintedCount = ILOVE20Group(GROUP_ADDRESS).totalSupply();
        for (uint256 i = 0; i < mentionedSenderIds.length; i++) {
            uint256 mentionedSenderId = mentionedSenderIds[i];
            if (mentionedSenderId == 0 || mentionedSenderId > mintedCount) {
                revert GroupNotExist();
            }
            for (uint256 j = 0; j < i; j++) {
                if (mentionedSenderIds[j] == mentionedSenderId) {
                    revert DuplicateMentionedSenderId();
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
        uint256 quotedMessageId
    ) internal returns (uint256 messageIndex) {
        messageIndex = _messagesByChat[groupId].length;
        _messagesByChat[groupId].push();

        StoredMessage storage message_ = _messagesByChat[groupId][messageIndex];
        message_.senderId = senderId;
        message_.senderAddress = msg.sender;
        message_.content = content;
        message_.blockNumber = block.number;
        message_.timestamp = block.timestamp;
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

    function _pageCount(uint256 total, uint256 offset, uint256 limit) internal pure returns (uint256) {
        if (limit == 0 || offset >= total) {
            return 0;
        }

        uint256 remaining = total - offset;
        return remaining < limit ? remaining : limit;
    }

    function _pageIndex(uint256 total, uint256 offset, uint256 index, bool reverse) internal pure returns (uint256) {
        if (!reverse) {
            return offset + index;
        }
        return total - 1 - offset - index;
    }

    function _roundByBlockNumber(uint256 blockNumber) internal view returns (uint256) {
        return (blockNumber - originBlocks) / phaseBlocks;
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
        result.round = _roundByBlockNumber(source.blockNumber);
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
            revert InvalidQuotedMessageId();
        }
    }
}
