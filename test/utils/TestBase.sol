// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChat} from "../../src/interfaces/IGroupChat.sol";
import {IGroupChatBanList} from "../../src/interfaces/IGroupChatBanList.sol";
import {IGroupChatDelegate} from "../../src/interfaces/IGroupChatDelegate.sol";
import {IGroupMember} from "../../src/interfaces/IGroupMember.sol";
import {IGovVotedBanSource} from "../../src/interfaces/sources/ban/IGovVotedBanSource.sol";
import {ITokenActionScopeManagerBase} from "../../src/interfaces/managers/ITokenActionScopeManagerBase.sol";
import {ITokenScopeManagerBase} from "../../src/interfaces/managers/ITokenScopeManagerBase.sol";

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function expectRevert(bytes4) external;
    function expectRevert(bytes calldata) external;
    function prank(address) external;
    function roll(uint256) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function toString(uint256 value) external pure returns (string memory);
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool value) internal pure {
        require(value, "ASSERT_TRUE");
    }

    function assertEq(uint256 left, uint256 right) internal pure {
        require(left == right, "ASSERT_EQ_UINT");
    }

    function assertEq(address left, address right) internal pure {
        require(left == right, "ASSERT_EQ_ADDRESS");
    }

    function assertEq(bytes32 left, bytes32 right) internal pure {
        require(left == right, "ASSERT_EQ_BYTES32");
    }

    function assertEq(bool left, bool right) internal pure {
        require(left == right, "ASSERT_EQ_BOOL");
    }

    function assertEq(bytes memory left, bytes memory right) internal pure {
        require(keccak256(left) == keccak256(right), "ASSERT_EQ_BYTES");
    }

    function assertEq(string memory left, string memory right) internal pure {
        require(keccak256(bytes(left)) == keccak256(bytes(right)), "ASSERT_EQ_STRING");
    }

    function assertEq(IGroupChat.PostRejectionReason left, IGroupChat.PostRejectionReason right) internal pure {
        require(left == right, "ASSERT_EQ_REASON");
    }

    function messagesTotal(IGroupChat target, uint256 groupId) internal view returns (uint256 total) {
        (, total) = target.messages(groupId, 0, 0, false);
    }

    function messagesByRoundTotal(IGroupChat target, uint256 groupId, uint256 round)
        internal
        view
        returns (uint256 total)
    {
        (, total) = target.messagesByRound(groupId, round, 0, 0, false);
    }

    function messagesBySenderIdTotal(IGroupChat target, uint256 groupId, uint256 senderId)
        internal
        view
        returns (uint256 total)
    {
        (, total) = target.messagesBySenderId(groupId, senderId, 0, 0, false);
    }

    function mentionedMessagesTotal(IGroupChat target, uint256 groupId, uint256 mentionedSenderId)
        internal
        view
        returns (uint256 total)
    {
        (, total) = target.messagesByMentionedSenderId(groupId, mentionedSenderId, 0, 0, false);
    }

    function mentionAllMessagesTotal(IGroupChat target, uint256 groupId) internal view returns (uint256 total) {
        (, total) = target.mentionAllMessages(groupId, 0, 0, false);
    }

    function senderIdsTotal(IGroupChat target, uint256 groupId) internal view returns (uint256 total) {
        (, total) = target.senderIds(groupId, 0, 0, false);
    }

    function groupIdsTotal(IGroupChat target) internal view returns (uint256 total) {
        (, total) = target.groupIds(0, 0, false);
    }

    function roundsTotal(IGroupChat target, uint256 groupId) internal view returns (uint256 total) {
        (, total) = target.rounds(groupId, 0, 0, false);
    }

    function memberIdsTotal(IGroupMember target, uint256 groupId) internal view returns (uint256 total) {
        (, total) = target.memberIds(groupId, 0, 0, false);
    }

    function delegatedGroupIdsTotal(IGroupChatDelegate target, uint256 delegateId)
        internal
        view
        returns (uint256 total)
    {
        (, , total) = target.delegatedGroupIds(delegateId, 0, 0, false);
    }

    function senderIdBanListTotal(IGroupChatBanList target, uint256 groupId) internal view returns (uint256 total) {
        (, , , total) = target.senderIdBanList(groupId, 0, 0, false);
    }

    function votedSenderIdsTotal(IGovVotedBanSource target, uint256 groupId) internal view returns (uint256 total) {
        (, , , , total) = target.votedSenderIds(groupId, 0, 0, false);
    }

    function votersBySenderIdTotal(IGovVotedBanSource target, uint256 groupId, uint256 senderId)
        internal
        view
        returns (uint256 total)
    {
        (, , , total) = target.votersBySenderId(groupId, senderId, 0, 0, false);
    }

    function tokensTotal(ITokenScopeManagerBase target) internal view returns (uint256 total) {
        (, , total) = target.tokens(0, 0, false);
    }

    function actionsTotal(ITokenActionScopeManagerBase target, address tokenAddress)
        internal
        view
        returns (uint256 total)
    {
        (, , total) = target.actions(tokenAddress, 0, 0, false);
    }

    function messagesOf(IGroupChat target, uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (IGroupChat.Message[] memory list)
    {
        (list, ) = target.messages(groupId, offset, limit, reverse);
    }

    function messagesByRoundOf(
        IGroupChat target,
        uint256 groupId,
        uint256 round,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (IGroupChat.Message[] memory list) {
        (list, ) = target.messagesByRound(groupId, round, offset, limit, reverse);
    }

    function messagesBySenderIdOf(
        IGroupChat target,
        uint256 groupId,
        uint256 senderId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (IGroupChat.Message[] memory list) {
        (list, ) = target.messagesBySenderId(groupId, senderId, offset, limit, reverse);
    }

    function messageIdsBySenderIdOf(
        IGroupChat target,
        uint256 groupId,
        uint256 senderId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (uint256[] memory list) {
        (list, ) = target.messageIdsBySenderId(groupId, senderId, offset, limit, reverse);
    }

    function messagesByMentionedSenderIdOf(
        IGroupChat target,
        uint256 groupId,
        uint256 mentionedSenderId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (IGroupChat.Message[] memory list) {
        (list, ) = target.messagesByMentionedSenderId(groupId, mentionedSenderId, offset, limit, reverse);
    }

    function messageIdsByMentionedSenderIdOf(
        IGroupChat target,
        uint256 groupId,
        uint256 mentionedSenderId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (uint256[] memory list) {
        (list, ) = target.messageIdsByMentionedSenderId(groupId, mentionedSenderId, offset, limit, reverse);
    }

    function mentionAllMessagesOf(
        IGroupChat target,
        uint256 groupId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (IGroupChat.Message[] memory list) {
        (list, ) = target.mentionAllMessages(groupId, offset, limit, reverse);
    }

    function mentionAllMessageIdsOf(
        IGroupChat target,
        uint256 groupId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (uint256[] memory list) {
        (list, ) = target.mentionAllMessageIds(groupId, offset, limit, reverse);
    }

    function senderIdsOf(IGroupChat target, uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory list)
    {
        (list, ) = target.senderIds(groupId, offset, limit, reverse);
    }

    function groupIdsOf(IGroupChat target, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory list)
    {
        (list, ) = target.groupIds(offset, limit, reverse);
    }

    function roundsOf(IGroupChat target, uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (IGroupChat.RoundSpan[] memory list)
    {
        (list, ) = target.rounds(groupId, offset, limit, reverse);
    }

    function memberIdsOf(IGroupMember target, uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory list)
    {
        (list, ) = target.memberIds(groupId, offset, limit, reverse);
    }
}
