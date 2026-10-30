// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IGroupChatErrors {
    error SourceNotContract(address dependency);
    error PluginNotContract(address dependency);
    error GroupNotExist(uint256 groupId);
    error ChatAlreadyActivated(uint256 groupId);
    error ChatNotActivated(uint256 groupId);
    error PostingNotAllowed(uint256 groupId);
    error RoundNotStarted(
        uint256 requiredRound,
        uint256 currentRound
    );
    error NotGroupOwner(uint256 groupId);
    error NotGroupOperator(
        uint256 groupId,
        uint256 operatorId
    );
    error NotMemberOwner(uint256 memberId);
    error Reentrant();
    error ContentEmpty();
    error ContentTooLong(
        uint256 length,
        uint256 maxLength
    );
    error TooManyMentionedSenderIds(
        uint256 length,
        uint256 maxLength
    );
    error DuplicateMemberId(uint256 memberId);
    error MessageNotFound(
        uint256 groupId,
        uint256 messageId
    );
    error QuotedMessageNotFound(
        uint256 groupId,
        uint256 messageId
    );
    error MentionAllUnauthorized(
        uint256 groupId,
        uint256 senderId
    );
    error ScopeRejected(
        uint256 groupId,
        uint256 senderId,
        address source
    );
    error BanRejected(
        uint256 groupId,
        uint256 senderId,
        address source
    );
    error ScopeSourceFailed(
        uint256 groupId,
        address source
    );
    error BanSourceFailed(
        uint256 groupId,
        address source
    );
}

interface IGroupChatEvents {
    event GroupChatActivated(
        uint256 indexed groupId,
        uint256 indexed ownerId,
        address indexed owner,
        bool postingAllowed,
        address scopeSource,
        address banSource,
        address beforePostPlugin,
        address afterPostPlugin
    );

    event PostingAllowedChanged(
        uint256 indexed groupId,
        uint256 indexed operatorId,
        address indexed operator,
        bool postingAllowed
    );

    event ScopeSourceChanged(
        uint256 indexed groupId,
        address indexed sourceAddress,
        uint256 indexed operatorId,
        address operator,
        address prevSourceAddress
    );

    event BanSourceChanged(
        uint256 indexed groupId,
        address indexed sourceAddress,
        uint256 indexed operatorId,
        address operator,
        address prevSourceAddress
    );

    event BeforePostPluginChanged(
        uint256 indexed groupId,
        address indexed pluginAddress,
        uint256 indexed operatorId,
        address operator,
        address prevPluginAddress
    );

    event AfterPostPluginChanged(
        uint256 indexed groupId,
        address indexed pluginAddress,
        uint256 indexed operatorId,
        address operator,
        address prevPluginAddress
    );

    event MessagePosted(
        uint256 indexed groupId,
        uint256 indexed messageId,
        uint256 indexed senderId,
        address sender,
        uint256 round,
        uint256 quotedMessageId,
        bool hasQuote,
        bool mentionAll,
        uint256 mentionedSenderCount,
        string content
    );

    event SenderMentioned(
        uint256 indexed groupId,
        uint256 indexed messageId,
        uint256 indexed mentionedSenderId
    );

    event AfterPostPluginFailed(
        uint256 indexed groupId,
        uint256 indexed messageId,
        uint256 round,
        address indexed pluginAddress,
        bytes32 errorHash,
        uint256 errorLength,
        bytes4 errorSelector
    );
}

interface IGroupChat is IGroupChatErrors, IGroupChatEvents {
    enum PostRejectionReason {
        None,
        GroupNotExist,
        SenderNotExist,
        ChatNotActivated,
        PostingNotAllowed,
        ScopeRejected,
        BanRejected,
        ScopeSourceFailed,
        BanSourceFailed
    }

    struct ChatInfo {
        uint256 groupId;
        address owner;
        bool activated;
        bool postingAllowed;
        address scopeSource;
        address banSource;
        address beforePostPlugin;
        address afterPostPlugin;
        address firstActivatedOwner;
        uint256 firstActivatedBlockNumber;
        uint256 firstActivatedTimestamp;
    }

    struct Message {
        uint256 groupId;
        uint256 senderId;
        address senderAddress;
        uint256 round;
        uint256 messageId;
        string content;
        uint256 blockNumber;
        uint256 timestamp;
        uint256[] mentionedSenderIds;
        bool mentionAll;
        uint256 quotedMessageId;
    }

    struct RoundSpan {
        uint256 round;
        uint256 startMessageId;
        uint256 endMessageId;
        uint256 messageCount;
    }

    function GROUP_ADDRESS() external view returns (address);

    function GROUP_ADMIN_ADDRESS() external view returns (address);

    function GROUP_DELEGATE_ADDRESS() external view returns (address);

    function PHASE_ADDRESS() external view returns (address);

    function MAX_CONTENT_LENGTH() external view returns (uint256);

    function MAX_MENTIONED_SENDER_IDS() external view returns (uint256);

    function activateChat(
        uint256 groupId,
        address scopeSourceAddress,
        address banSourceAddress,
        address beforePostPluginAddress,
        address afterPostPluginAddress
    ) external;

    function setPostingAllowed(uint256 groupId, uint256 operatorId, bool postingAllowed) external;

    function setScopeSource(uint256 groupId, uint256 operatorId, address scopeSourceAddress) external;

    function setBanSource(uint256 groupId, uint256 operatorId, address banSourceAddress) external;

    function setBeforePostPlugin(uint256 groupId, uint256 operatorId, address beforePostPluginAddress) external;

    function setAfterPostPlugin(uint256 groupId, uint256 operatorId, address afterPostPluginAddress) external;

    function post(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId
    ) external;

    function chatInfo(uint256 groupId) external view returns (ChatInfo memory info);

    function chatInfosByGroupIds(uint256[] calldata requestedGroupIds) external view returns (ChatInfo[] memory);

    function isPostingAllowed(uint256 groupId) external view returns (bool);

    function scopeSource(uint256 groupId) external view returns (address);

    function banSource(uint256 groupId) external view returns (address);

    function beforePostPlugin(uint256 groupId) external view returns (address);

    function afterPostPlugin(uint256 groupId) external view returns (address);

    function canPost(uint256 groupId, uint256 senderId)
        external
        view
        returns (bool allowed, PostRejectionReason reason);

    function messages(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory messageList, uint256 totalCount);

    function message(uint256 groupId, uint256 messageId) external view returns (Message memory storedMessage);

    function messagesByRound(uint256 groupId, uint256 round, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory messageList, uint256 totalCount);

    function messagesBySenderId(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory messageList, uint256 totalCount);

    function messageIdsBySenderId(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory messageIds, uint256 totalCount);

    function messagesByMentionedSenderId(
        uint256 groupId,
        uint256 mentionedSenderId,
        uint256 offset,
        uint256 limit,
        bool reverse
    )
        external
        view
        returns (Message[] memory messageList, uint256 totalCount);

    function messageIdsByMentionedSenderId(
        uint256 groupId,
        uint256 mentionedSenderId,
        uint256 offset,
        uint256 limit,
        bool reverse
    )
        external
        view
        returns (uint256[] memory messageIds, uint256 totalCount);

    function mentionAllMessages(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (Message[] memory messageList, uint256 totalCount);

    function mentionAllMessageIds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory messageIds, uint256 totalCount);

    function senderIds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory senderIdList, uint256 totalCount);

    function groupIds(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory groupIdList, uint256 totalCount);

    function currentRound() external view returns (uint256);

    function rounds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (RoundSpan[] memory roundList, uint256 totalCount);

    function roundInfo(uint256 groupId, uint256 round) external view returns (RoundSpan memory roundSpan);

    function roundInfosByRounds(uint256 groupId, uint256[] calldata requestedRounds)
        external
        view
        returns (RoundSpan[] memory);
}
