// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupChat} from "../src/GroupChat.sol";
import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract GroupChatMessagesTest is GroupChatFixture {
    function testT040_post_ownerCanPostWithOwnedSenderId() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "hello");

        assertEq(chat.messagesCount(groupId), 1);

        IGroupChat.Message[] memory result = chat.messages(groupId, 0, 1, false);
        assertEq(result.length, 1);
        assertEq(result[0].groupId, groupId);
        assertEq(result[0].senderId, senderId);
        assertEq(result[0].senderAddress, senderOwner);
        assertEq(result[0].round, 0);
        assertEq(result[0].messageId, 1);
        assertEq(result[0].content, "hello");
        assertEq(result[0].blockNumber, originBlocks);
        assertEq(result[0].timestamp, block.timestamp);
        assertEq(result[0].mentionedSenderIds.length, 0);
        assertTrue(!result[0].mentionAll);
        assertEq(result[0].quotedMessageId, 0);
    }

    function testT041_crossGroupPostWithoutPluginIsAllowedByDefault() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "cross-group");

        IGroupChat.Message[] memory result = chat.messages(groupId, 0, 1, false);
        assertEq(result.length, 1);
        assertEq(result[0].groupId, groupId);
        assertEq(result[0].senderId, senderId);
        assertTrue(groupId != senderId);
    }

    function testT042_post_revertsForNonSenderOwner() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(other);
        vm.expectRevert(IGroupChatErrors.SenderAddressNotSenderIdOwner.selector);
        _post(groupId, senderId, "hello");
    }

    function testT043T044T045T046T047_postInvalidCases() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.roll(originBlocks);
        vm.prank(delegateIdOwner);
        vm.expectRevert(IGroupChatErrors.SenderAddressNotSenderIdOwner.selector);
        _post(groupId, senderId, "delegate-send");

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, false);

        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.PostingNotAllowed.selector);
        _post(groupId, senderId, "stopped");

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, true);

        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.ContentEmpty.selector);
        _post(groupId, senderId, "");

        uint256 maxContentLength = chat.MAX_CONTENT_LENGTH();
        bytes memory tooLongBytes = new bytes(maxContentLength + 1);
        string memory tooLong = string(tooLongBytes);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.ContentTooLong.selector, maxContentLength + 1, maxContentLength)
        );
        _post(groupId, senderId, tooLong);

        GroupChat futureChat = new GroupChat(
            address(baseGroupAdmin),
            block.number + 1000,
            phaseBlocks,
            maxContentLength,
            maxMentionedSenderIds
        );
        vm.prank(chatOwner);
        futureChat.activateChat(groupId, address(0), address(0), address(0), address(0));

        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.RoundNotStarted.selector);
        futureChat.post(groupId, senderId, "early", _emptyMentionedSenderIds(), false, 0);
    }

    function testT048_postStoresMentionedSenderIdsAndMentionMessageIds() public {
        _activateEmpty();

        uint256[] memory mentionedSenderIds = new uint256[](2);
        mentionedSenderIds[0] = otherGroupId;
        mentionedSenderIds[1] = delegateId;

        vm.roll(originBlocks);
        vm.recordLogs();
        vm.prank(senderOwner);
        _postWithMentionedSenderIds(groupId, senderId, "hello @two", mentionedSenderIds, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 3);
        assertEq(logs[0].topics[0], POST_MESSAGE_SIG);
        assertEq(logs[1].topics[0], MENTION_SENDER_ID_SIG);
        assertEq(logs[1].topics[1], bytes32(groupId));
        assertEq(logs[1].topics[2], bytes32(otherGroupId));
        assertEq(_decodeMessageId(logs[1].data), 1);
        assertEq(logs[2].topics[0], MENTION_SENDER_ID_SIG);
        assertEq(logs[2].topics[1], bytes32(groupId));
        assertEq(logs[2].topics[2], bytes32(delegateId));
        assertEq(_decodeMessageId(logs[2].data), 1);

        IGroupChat.Message[] memory result = chat.messages(groupId, 0, 1, false);
        assertEq(result.length, 1);
        assertEq(result[0].mentionedSenderIds.length, 2);
        assertEq(result[0].mentionedSenderIds[0], otherGroupId);
        assertEq(result[0].mentionedSenderIds[1], delegateId);
        assertTrue(!result[0].mentionAll);
        assertEq(result[0].quotedMessageId, 0);

        assertEq(chat.messagesByMentionCount(groupId, otherGroupId), 1);
        assertEq(chat.messagesByMentionCount(groupId, delegateId), 1);
        assertEq(chat.messagesByMentionCount(groupId, 999999), 0);

        IGroupChat.Message[] memory byMention = chat.messagesByMention(groupId, delegateId, 0, 10, false);
        assertEq(byMention.length, 1);
        assertEq(byMention[0].messageId, 1);
        assertEq(byMention[0].mentionedSenderIds.length, 2);

        uint256[] memory messageIds = chat.messageIdsByMention(groupId, otherGroupId, 0, 10, false);
        assertEq(messageIds.length, 1);
        assertEq(messageIds[0], 1);
        assertEq(chat.messagesByMention(groupId, 999999, 0, 10, false).length, 0);
        assertEq(chat.messageIdsByMention(groupId, 999999, 0, 10, false).length, 0);

        uint256[] memory futureMentionedSenderIds = new uint256[](1);
        futureMentionedSenderIds[0] = 999999;
        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.GroupNotExist.selector);
        _postWithMentionedSenderIds(groupId, senderId, "future mention", futureMentionedSenderIds, false);
    }

    function testT049_postRejectsDuplicateMentionedSenderIdsAndRestrictsMentionAll() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        uint256[] memory duplicateMentionedSenderIds = new uint256[](2);
        duplicateMentionedSenderIds[0] = otherGroupId;
        duplicateMentionedSenderIds[1] = otherGroupId;

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.DuplicateMentionedSenderId.selector);
        _postWithMentionedSenderIds(groupId, senderId, "dup", duplicateMentionedSenderIds, false);

        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.MentionAllUnauthorized.selector);
        _postWithMentionedSenderIds(groupId, senderId, "@all-sender", _emptyMentionedSenderIds(), true);

        vm.prank(chatOwner);
        vm.recordLogs();
        _postWithMentionedSenderIds(groupId, groupId, "@all-owner", _emptyMentionedSenderIds(), true);
        Vm.Log[] memory mentionAllLogs = vm.getRecordedLogs();

        assertEq(mentionAllLogs.length, 2);
        assertEq(mentionAllLogs[0].topics[0], POST_MESSAGE_SIG);
        assertEq(mentionAllLogs[1].topics[0], MENTION_ALL_SIG);
        assertEq(mentionAllLogs[1].topics[1], bytes32(groupId));
        assertEq(_decodeMessageId(mentionAllLogs[1].data), 1);

        vm.prank(other);
        _post(groupId, otherGroupId, "plain");

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        vm.prank(delegateIdOwner);
        _postWithMentionedSenderIds(groupId, delegateId, "@all-delegate", _emptyMentionedSenderIds(), true);

        uint256 adminId = groupNft.mint(senderOwner);
        uint256[] memory adminIds = new uint256[](1);
        adminIds[0] = adminId;
        vm.prank(chatOwner);
        baseGroupAdmin.addAdmins(groupId, adminIds);
        vm.prank(senderOwner);
        groupDefaults.setDefaultGroupId(adminId);
        vm.prank(senderOwner);
        _postWithMentionedSenderIds(groupId, adminId, "@all-admin", _emptyMentionedSenderIds(), true);

        IGroupChat.Message[] memory result = chat.messages(groupId, 0, 10, false);
        assertEq(result.length, 4);
        assertTrue(result[0].mentionAll);
        assertTrue(!result[1].mentionAll);
        assertTrue(result[2].mentionAll);
        assertTrue(result[3].mentionAll);

        assertEq(chat.messagesByMentionAllCount(groupId), 3);

        IGroupChat.Message[] memory byMentionAll = chat.messagesByMentionAll(groupId, 0, 10, false);
        assertEq(byMentionAll.length, 3);
        assertEq(byMentionAll[0].messageId, 1);
        assertEq(byMentionAll[1].messageId, 3);
        assertEq(byMentionAll[2].messageId, 4);

        IGroupChat.Message[] memory byMentionAllReverse = chat.messagesByMentionAll(groupId, 0, 1, true);
        assertEq(byMentionAllReverse.length, 1);
        assertEq(byMentionAllReverse[0].messageId, 4);

        uint256[] memory messageIds = chat.messageIdsByMentionAll(groupId, 0, 10, false);
        assertEq(messageIds.length, 3);
        assertEq(messageIds[0], 1);
        assertEq(messageIds[1], 3);
        assertEq(messageIds[2], 4);

        uint256[] memory reverseMessageIds = chat.messageIdsByMentionAll(groupId, 1, 1, true);
        assertEq(reverseMessageIds.length, 1);
        assertEq(reverseMessageIds[0], 3);
    }

    function testT050_roundInfoAcrossRounds() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "r0-0");
        vm.prank(other);
        _post(groupId, otherGroupId, "r0-1");

        vm.roll(originBlocks + phaseBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "r1-0");

        assertEq(chat.roundsCount(groupId), 2);

        IGroupChat.RoundSpan memory round0 = chat.roundInfo(groupId, 0);
        assertEq(round0.round, 0);
        assertEq(round0.startMessageId, 1);
        assertEq(round0.endMessageId, 2);
        assertEq(round0.messageCount, 2);

        IGroupChat.RoundSpan memory round1 = chat.roundInfo(groupId, 1);
        assertEq(round1.round, 1);
        assertEq(round1.startMessageId, 3);
        assertEq(round1.endMessageId, 3);
        assertEq(round1.messageCount, 1);

        uint256[] memory rounds = new uint256[](3);
        rounds[0] = 1;
        rounds[1] = 99;
        rounds[2] = 0;

        IGroupChat.RoundSpan[] memory batch = chat.roundInfos(groupId, rounds);
        assertEq(batch.length, 3);
        assertEq(batch[0].round, 1);
        assertEq(batch[0].startMessageId, 3);
        assertEq(batch[0].endMessageId, 3);
        assertEq(batch[0].messageCount, 1);
        assertEq(batch[1].round, 99);
        assertEq(batch[1].startMessageId, 0);
        assertEq(batch[1].endMessageId, 0);
        assertEq(batch[1].messageCount, 0);
        assertEq(batch[2].round, 0);
        assertEq(batch[2].startMessageId, 1);
        assertEq(batch[2].endMessageId, 2);
        assertEq(batch[2].messageCount, 2);
    }

    function testT051T052T053T054T055_roundAndPaginationBoundaries() public {
        _activateEmpty();

        assertEq(chat.messagesByRoundCount(groupId, 99), 0);
        IGroupChat.RoundSpan memory emptyRound = chat.roundInfo(groupId, 99);
        assertEq(emptyRound.round, 99);
        assertEq(emptyRound.startMessageId, 0);
        assertEq(emptyRound.endMessageId, 0);
        assertEq(emptyRound.messageCount, 0);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "m0");
        vm.prank(other);
        _post(groupId, otherGroupId, "m1");
        vm.prank(senderOwner);
        _post(groupId, senderId, "m2");

        vm.roll(originBlocks + phaseBlocks);
        vm.prank(other);
        _post(groupId, otherGroupId, "m3");

        vm.roll(originBlocks + phaseBlocks * 2);
        vm.prank(senderOwner);
        _post(groupId, senderId, "m4");

        IGroupChat.Message[] memory messagesForward = chat.messages(groupId, 1, 2, false);
        assertEq(messagesForward.length, 2);
        assertEq(messagesForward[0].messageId, 2);
        assertEq(messagesForward[1].messageId, 3);

        IGroupChat.Message[] memory messagesReverse = chat.messages(groupId, 1, 2, true);
        assertEq(messagesReverse.length, 2);
        assertEq(messagesReverse[0].messageId, 4);
        assertEq(messagesReverse[1].messageId, 3);

        IGroupChat.Message[] memory round0Reverse = chat.messagesByRound(groupId, 0, 1, 2, true);
        assertEq(round0Reverse.length, 2);
        assertEq(round0Reverse[0].messageId, 2);
        assertEq(round0Reverse[1].messageId, 1);

        IGroupChat.RoundSpan[] memory roundsForward = chat.rounds(groupId, 1, 2, false);
        assertEq(roundsForward.length, 2);
        assertEq(roundsForward[0].round, 1);
        assertEq(roundsForward[1].round, 2);

        IGroupChat.RoundSpan[] memory roundsReverse = chat.rounds(groupId, 1, 2, true);
        assertEq(roundsReverse.length, 2);
        assertEq(roundsReverse[0].round, 1);
        assertEq(roundsReverse[1].round, 0);

        assertEq(chat.messages(groupId, 99, 10, false).length, 0);
        assertEq(chat.messagesByRound(groupId, 0, 99, 10, false).length, 0);
        assertEq(chat.rounds(groupId, 99, 10, false).length, 0);
        assertEq(chat.messages(groupId, 0, 0, false).length, 0);
        assertEq(chat.messagesByRound(groupId, 0, 0, 0, false).length, 0);
        assertEq(chat.rounds(groupId, 0, 0, false).length, 0);
    }

    function testT060AndT062_messagesBySenderAndMessageIdsStayAligned() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "s-0");
        vm.prank(other);
        _post(groupId, otherGroupId, "o-1");
        vm.prank(senderOwner);
        _post(groupId, senderId, "s-2");

        assertEq(chat.messagesBySenderCount(groupId, senderId), 2);

        IGroupChat.Message[] memory senderMessages = chat.messagesBySender(groupId, senderId, 0, 10, false);
        assertEq(senderMessages.length, 2);
        assertEq(senderMessages[0].messageId, 1);
        assertEq(senderMessages[1].messageId, 3);

        uint256[] memory messageIds = chat.messageIdsBySender(groupId, senderId, 0, 10, false);
        assertEq(messageIds.length, 2);
        assertEq(messageIds[0], 1);
        assertEq(messageIds[1], 3);

        uint256[] memory reverseMessageIds = chat.messageIdsBySender(groupId, senderId, 0, 10, true);
        assertEq(reverseMessageIds.length, 2);
        assertEq(reverseMessageIds[0], 3);
        assertEq(reverseMessageIds[1], 1);
    }

    function testT061T064_senderCountMatchesAndNonexistentSenderDoesNotRevert() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "m0");
        vm.prank(senderOwner);
        _post(groupId, senderId, "m1");

        assertEq(chat.messagesBySenderCount(groupId, senderId), 2);
        assertEq(chat.messagesBySender(groupId, senderId, 0, 10, false).length, 2);
        assertEq(chat.messageIdsBySender(groupId, senderId, 0, 10, false).length, 2);

        assertEq(chat.messagesBySenderCount(groupId, 999999), 0);
        assertEq(chat.messagesBySender(groupId, 999999, 0, 10, false).length, 0);
        assertEq(chat.messageIdsBySender(groupId, 999999, 0, 10, false).length, 0);
    }

    function testT063T068_senderEmptyViewsAndPaginationBoundaries() public {
        _activateEmpty();

        assertEq(chat.messagesBySenderCount(groupId, 999), 0);
        assertEq(chat.messagesBySender(groupId, 999, 0, 10, false).length, 0);
        assertEq(chat.messageIdsBySender(groupId, 999, 0, 10, false).length, 0);
        assertEq(chat.senderIdsCount(groupId), 0);
        assertEq(chat.senderIds(groupId, 0, 0, false).length, 0);
        assertEq(chat.senderIds(groupId, 99, 10, false).length, 0);
    }

    function testT065AndT066AndT067_senderIdsKeepFirstAppearanceOrder() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "s-0");
        vm.prank(other);
        _post(groupId, otherGroupId, "o-1");
        vm.prank(senderOwner);
        _post(groupId, senderId, "s-2");

        assertEq(chat.senderIdsCount(groupId), 2);

        uint256[] memory senders = chat.senderIds(groupId, 0, 10, false);
        assertEq(senders.length, 2);
        assertEq(senders[0], senderId);
        assertEq(senders[1], otherGroupId);

        uint256[] memory reverseSenders = chat.senderIds(groupId, 0, 10, true);
        assertEq(reverseSenders.length, 2);
        assertEq(reverseSenders[0], otherGroupId);
        assertEq(reverseSenders[1], senderId);
    }

    function testT083_messageEventActsAsSignalAndBodyComesFromView() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.recordLogs();
        vm.prank(senderOwner);
        _post(groupId, senderId, "signal");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], POST_MESSAGE_SIG);
        (uint256 messageRound, uint256 messageId) = _decodePostMessage(logs[0].data);
        assertEq(messageRound, 0);
        assertEq(messageId, 1);

        IGroupChat.Message memory fetched = chat.message(groupId, messageId);
        assertEq(fetched.content, "signal");
        assertEq(fetched.messageId, messageId);
        assertEq(fetched.round, messageRound);
        assertEq(fetched.senderId, senderId);
        assertEq(fetched.mentionedSenderIds.length, 0);
        assertTrue(!fetched.mentionAll);
        assertEq(fetched.quotedMessageId, 0);
    }

    function testT084_messageViewReadsSingleMessageAndRevertsWhenMissing() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "single");

        IGroupChat.Message memory fetched = chat.message(groupId, 1);
        assertEq(fetched.groupId, groupId);
        assertEq(fetched.senderId, senderId);
        assertEq(fetched.content, "single");
        assertEq(fetched.messageId, 1);
        assertEq(fetched.quotedMessageId, 0);

        vm.expectRevert(IGroupChatErrors.InvalidMessageId.selector);
        chat.message(groupId, 0);

        vm.expectRevert(IGroupChatErrors.InvalidMessageId.selector);
        chat.message(groupId, 2);
    }

    function testT085_postStoresQuotedMessageIdAndRejectsInvalidQuote() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "m0");

        vm.prank(senderOwner);
        _post(groupId, senderId, "m1");

        vm.prank(other);
        _postWithQuote(groupId, otherGroupId, "quote-m0", 1);

        IGroupChat.Message memory fetched = chat.message(groupId, 3);
        assertEq(fetched.messageId, 3);
        assertEq(fetched.quotedMessageId, 1);

        vm.prank(other);
        vm.expectRevert(IGroupChatErrors.InvalidQuotedMessageId.selector);
        _postWithQuote(groupId, otherGroupId, "future", 4);
    }

    function testT086_postRejectsTooManyMentionedSenderIds() public {
        _activateEmpty();

        uint256 maxMentionedSenderIds = chat.MAX_MENTIONED_SENDER_IDS();
        uint256[] memory mentionedSenderIds = new uint256[](maxMentionedSenderIds + 1);
        for (uint256 i = 0; i < maxMentionedSenderIds; i++) {
            mentionedSenderIds[i] = senderId;
        }
        mentionedSenderIds[maxMentionedSenderIds] = otherGroupId;

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGroupChatErrors.TooManyMentionedSenderIds.selector, maxMentionedSenderIds + 1, maxMentionedSenderIds
            )
        );
        _postWithMentionedSenderIds(groupId, senderId, "too-many", mentionedSenderIds, false);
    }
}
