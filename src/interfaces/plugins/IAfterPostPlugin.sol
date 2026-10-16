// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IAfterPostPlugin {
    function afterPost(
        uint256 groupId,
        uint256 senderId,
        address senderAddress,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId,
        uint256 messageId,
        uint256 blockNumber,
        uint256 timestamp
    ) external;
}
