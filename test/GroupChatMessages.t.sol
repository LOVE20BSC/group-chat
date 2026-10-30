// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupChat} from "../src/GroupChat.sol";
import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockPhase} from "./mocks/MockPhase.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract GroupChatMessagesTest is GroupChatFixture {
    function testT040_post_ownerCanPostWithOwnedSenderId() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "hello");

        assertEq(messagesTotal(chat, groupId), 1);

        IGroupChat.Message[] memory result = messagesOf(chat, groupId, 0, 1, false);
        assertEq(result.length, 1);
        assertEq(result[0].groupId, groupId);
        assertEq(result[0].senderId, senderId);
        assertEq(result[0].senderAddress, senderOwner);
        assertEq(result[0].round, 1);
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

        IGroupChat.Message[] memory result = messagesOf(chat, groupId, 0, 1, false);
        assertEq(result.length, 1);
        assertEq(result[0].groupId, groupId);
        assertEq(result[0].senderId, senderId);
        assertTrue(groupId != senderId);
    }

    function testT042_post_revertsForNonSenderOwner() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotMemberOwner.selector, senderId));
        _post(groupId, senderId, "hello");
    }

    function testT042B_post_rejectsMissingSenderId() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999_999))
        );
        _post(groupId, 999_999, "missing sender");
    }

    function testT043T044T045T046T047_postInvalidCases() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.roll(originBlocks);
        vm.prank(delegateIdOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotMemberOwner.selector, senderId));
        _post(groupId, senderId, "delegate-send");

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, false);

        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.PostingNotAllowed.selector, groupId));
        _post(groupId, senderId, "stopped");

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, true);

        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.ContentEmpty.selector));
        _post(groupId, senderId, "");

        uint256 maxContentLength = chat.MAX_CONTENT_LENGTH();
        bytes memory tooLongBytes = new bytes(maxContentLength + 1);
        string memory tooLong = string(tooLongBytes);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.ContentTooLong.selector, maxContentLength + 1, maxContentLength)
        );
        _post(groupId, senderId, tooLong);

        MockPhase futurePhase = new MockPhase(block.number + 1000, phaseBlocks);
        GroupChat futureChat =
            new GroupChat(address(baseGroupAdmin), address(futurePhase), maxContentLength, maxMentionedSenderIds);
        vm.prank(chatOwner);
        futureChat.activateChat(groupId, address(0), address(0), address(0), address(0));

        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.RoundNotStarted.selector, 1, 0));
        futureChat.post(groupId, senderId, "early", _emptyMentionedSenderIds(), false, 0);
    }

    function testT048_postStoresMentionedSenderIdsAndMentionMessageIds() public {
        _activateEmpty();

        uint256 thirdMentionedSenderId = groupNft.mint(other);
        uint256 fourthMentionedSenderId = groupNft.mint(other);
        uint256[] memory mentionedSenderIds = new uint256[](4);
        mentionedSenderIds[0] = otherGroupId;
        mentionedSenderIds[1] = delegateId;
        mentionedSenderIds[2] = thirdMentionedSenderId;
        mentionedSenderIds[3] = fourthMentionedSenderId;

        vm.roll(originBlocks);
        // Two priming posts keep `messageId` (3) apart from `groupId` (1), `senderId` (2) and the mention count (4).
        vm.prank(senderOwner);
        _post(groupId, senderId, "prime one");
        vm.prank(senderOwner);
        _post(groupId, senderId, "prime two");
        vm.recordLogs();
        vm.prank(senderOwner);
        _postWithMentionedSenderIds(groupId, senderId, "hello @two", mentionedSenderIds, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 5);
        assertEq(logs[0].topics[0], MESSAGE_POSTED_SIG);
        assertEq(logs[0].topics[1], bytes32(groupId));
        assertEq(logs[0].topics[2], bytes32(uint256(3)));
        assertEq(logs[0].topics[3], bytes32(senderId));
        (
            address postedSender,
            uint256 postedRound,
            uint256 postedQuotedMessageId,
            bool postedHasQuote,
            bool postedMentionAll,
            uint256 postedMentionedSenderCount,
            string memory postedContent
        ) = _decodeMessagePostedData(logs[0].data);
        assertEq(postedSender, senderOwner);
        assertEq(postedRound, 1);
        assertEq(postedContent, "hello @two");
        assertEq(postedQuotedMessageId, 0);
        assertTrue(!postedHasQuote);
        assertTrue(!postedMentionAll);
        assertEq(postedMentionedSenderCount, 4);
        assertEq(postedMentionedSenderCount, logs.length - 1);
        for (uint256 i = 0; i < mentionedSenderIds.length; i++) {
            assertEq(logs[i + 1].topics[0], SENDER_MENTIONED_SIG);
            assertEq(logs[i + 1].topics[1], bytes32(groupId));
            assertEq(uint256(logs[i + 1].topics[2]), 3);
            assertEq(uint256(logs[i + 1].topics[3]), mentionedSenderIds[i]);
        }

        IGroupChat.Message[] memory result = messagesOf(chat, groupId, 2, 1, false);
        assertEq(result.length, 1);
        assertEq(result[0].mentionedSenderIds.length, 4);
        assertEq(result[0].mentionedSenderIds[0], otherGroupId);
        assertEq(result[0].mentionedSenderIds[1], delegateId);
        assertEq(result[0].mentionedSenderIds[2], thirdMentionedSenderId);
        assertEq(result[0].mentionedSenderIds[3], fourthMentionedSenderId);
        assertTrue(!result[0].mentionAll);
        assertEq(result[0].quotedMessageId, 0);

        assertEq(mentionedMessagesTotal(chat, groupId, otherGroupId), 1);
        assertEq(mentionedMessagesTotal(chat, groupId, delegateId), 1);
        assertEq(mentionedMessagesTotal(chat, groupId, 999999), 0);

        IGroupChat.Message[] memory byMention = messagesByMentionedSenderIdOf(chat, groupId, delegateId, 0, 10, false);
        assertEq(byMention.length, 1);
        assertEq(byMention[0].messageId, 3);
        assertEq(byMention[0].mentionedSenderIds.length, 4);

        uint256[] memory messageIds = messageIdsByMentionedSenderIdOf(chat, groupId, otherGroupId, 0, 10, false);
        assertEq(messageIds.length, 1);
        assertEq(messageIds[0], 3);
        assertEq(messagesByMentionedSenderIdOf(chat, groupId, 999999, 0, 10, false).length, 0);
        assertEq(messageIdsByMentionedSenderIdOf(chat, groupId, 999999, 0, 10, false).length, 0);

        uint256[] memory futureMentionedSenderIds = new uint256[](1);
        futureMentionedSenderIds[0] = 999999;
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999_999))
        );
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
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.DuplicateMemberId.selector, otherGroupId));
        _postWithMentionedSenderIds(groupId, senderId, "dup", duplicateMentionedSenderIds, false);

        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.MentionAllUnauthorized.selector, groupId, senderId));
        _postWithMentionedSenderIds(groupId, senderId, "@all-sender", _emptyMentionedSenderIds(), true);

        vm.prank(chatOwner);
        vm.recordLogs();
        _postWithMentionedSenderIds(groupId, groupId, "@all-owner", _emptyMentionedSenderIds(), true);
        Vm.Log[] memory mentionAllLogs = vm.getRecordedLogs();

        assertEq(mentionAllLogs.length, 1);
        assertEq(mentionAllLogs[0].topics[0], MESSAGE_POSTED_SIG);
        assertEq(mentionAllLogs[0].topics[1], bytes32(groupId));
        assertEq(mentionAllLogs[0].topics[2], bytes32(uint256(1)));
        (, , , , bool mentionAllFlag, uint256 emittedMentionedSenderCount, ) =
            _decodeMessagePostedData(mentionAllLogs[0].data);
        assertTrue(mentionAllFlag);
        assertEq(emittedMentionedSenderCount, 0);

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
        baseGroupAdmin.addAdmins(groupId, groupId, adminIds);
        vm.prank(senderOwner);
        _postWithMentionedSenderIds(groupId, adminId, "@all-admin", _emptyMentionedSenderIds(), true);

        IGroupChat.Message[] memory result = messagesOf(chat, groupId, 0, 10, false);
        assertEq(result.length, 4);
        assertTrue(result[0].mentionAll);
        assertTrue(!result[1].mentionAll);
        assertTrue(result[2].mentionAll);
        assertTrue(result[3].mentionAll);

        assertEq(mentionAllMessagesTotal(chat, groupId), 3);

        IGroupChat.Message[] memory byMentionAll = mentionAllMessagesOf(chat, groupId, 0, 10, false);
        assertEq(byMentionAll.length, 3);
        assertEq(byMentionAll[0].messageId, 1);
        assertEq(byMentionAll[1].messageId, 3);
        assertEq(byMentionAll[2].messageId, 4);

        IGroupChat.Message[] memory byMentionAllReverse = mentionAllMessagesOf(chat, groupId, 0, 1, true);
        assertEq(byMentionAllReverse.length, 1);
        assertEq(byMentionAllReverse[0].messageId, 4);

        uint256[] memory messageIds = mentionAllMessageIdsOf(chat, groupId, 0, 10, false);
        assertEq(messageIds.length, 3);
        assertEq(messageIds[0], 1);
        assertEq(messageIds[1], 3);
        assertEq(messageIds[2], 4);

        uint256[] memory reverseMessageIds = mentionAllMessageIdsOf(chat, groupId, 1, 1, true);
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

        assertEq(roundsTotal(chat, groupId), 2);

        IGroupChat.RoundSpan memory round0 = chat.roundInfo(groupId, 1);
        assertEq(round0.round, 1);
        assertEq(round0.startMessageId, 1);
        assertEq(round0.endMessageId, 2);
        assertEq(round0.messageCount, 2);

        IGroupChat.RoundSpan memory round1 = chat.roundInfo(groupId, 2);
        assertEq(round1.round, 2);
        assertEq(round1.startMessageId, 3);
        assertEq(round1.endMessageId, 3);
        assertEq(round1.messageCount, 1);

        uint256[] memory rounds = new uint256[](3);
        rounds[0] = 2;
        rounds[1] = 99;
        rounds[2] = 1;

        IGroupChat.RoundSpan[] memory batch = chat.roundInfosByRounds(groupId, rounds);
        assertEq(batch.length, 3);
        assertEq(batch[0].round, 2);
        assertEq(batch[0].startMessageId, 3);
        assertEq(batch[0].endMessageId, 3);
        assertEq(batch[0].messageCount, 1);
        assertEq(batch[1].round, 99);
        assertEq(batch[1].startMessageId, 0);
        assertEq(batch[1].endMessageId, 0);
        assertEq(batch[1].messageCount, 0);
        assertEq(batch[2].round, 1);
        assertEq(batch[2].startMessageId, 1);
        assertEq(batch[2].endMessageId, 2);
        assertEq(batch[2].messageCount, 2);
    }

    function testT050B_messageRoundIsFrozenWhenPhaseIsRecalibrated() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "round-1");

        vm.roll(originBlocks + phaseBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "round-2");
        assertEq(chat.currentRound(), 2);

        phase.setPhase(originBlocks, phaseBlocks / 2);
        assertEq(chat.currentRound(), 3);

        IGroupChat.Message memory second = chat.message(groupId, 2);
        assertEq(second.round, 2);
        assertEq(messagesByRoundTotal(chat, groupId, 2), 1);
        assertEq(messagesByRoundTotal(chat, groupId, 3), 0);
        assertEq(messagesByRoundOf(chat, groupId, 2, 0, 10, false)[0].messageId, 2);

        vm.prank(senderOwner);
        _post(groupId, senderId, "round-3");

        assertEq(chat.message(groupId, 3).round, 3);
        assertEq(chat.roundInfo(groupId, 2).messageCount, 1);
        assertEq(chat.roundInfo(groupId, 3).messageCount, 1);
        assertEq(roundsTotal(chat, groupId), 3);
    }

    function testT051T052T053T054T055_roundAndPaginationBoundaries() public {
        _activateEmpty();

        assertEq(messagesByRoundTotal(chat, groupId, 99), 0);
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

        IGroupChat.Message[] memory messagesForward = messagesOf(chat, groupId, 1, 2, false);
        assertEq(messagesForward.length, 2);
        assertEq(messagesForward[0].messageId, 2);
        assertEq(messagesForward[1].messageId, 3);

        IGroupChat.Message[] memory messagesReverse = messagesOf(chat, groupId, 1, 2, true);
        assertEq(messagesReverse.length, 2);
        assertEq(messagesReverse[0].messageId, 4);
        assertEq(messagesReverse[1].messageId, 3);

        IGroupChat.Message[] memory round0Reverse = messagesByRoundOf(chat, groupId, 1, 1, 2, true);
        assertEq(round0Reverse.length, 2);
        assertEq(round0Reverse[0].messageId, 2);
        assertEq(round0Reverse[1].messageId, 1);

        IGroupChat.RoundSpan[] memory roundsForward = roundsOf(chat, groupId, 1, 2, false);
        assertEq(roundsForward.length, 2);
        assertEq(roundsForward[0].round, 2);
        assertEq(roundsForward[1].round, 3);

        IGroupChat.RoundSpan[] memory roundsReverse = roundsOf(chat, groupId, 1, 2, true);
        assertEq(roundsReverse.length, 2);
        assertEq(roundsReverse[0].round, 2);
        assertEq(roundsReverse[1].round, 1);

        (IGroupChat.Message[] memory outOfRange, uint256 outOfRangeTotal) = chat.messages(groupId, 99, 10, false);
        assertEq(outOfRange.length, 0);
        assertEq(outOfRangeTotal, 5);

        (IGroupChat.Message[] memory roundOutOfRange, uint256 roundOutOfRangeTotal) =
            chat.messagesByRound(groupId, 1, 99, 10, false);
        assertEq(roundOutOfRange.length, 0);
        assertEq(roundOutOfRangeTotal, 3);

        (IGroupChat.RoundSpan[] memory roundsOutOfRange, uint256 roundsOutOfRangeTotal) =
            chat.rounds(groupId, 99, 10, false);
        assertEq(roundsOutOfRange.length, 0);
        assertEq(roundsOutOfRangeTotal, 3);

        (IGroupChat.Message[] memory messagesCountOnly, uint256 messagesCountOnlyTotal) =
            chat.messages(groupId, 0, 0, false);
        assertEq(messagesCountOnly.length, 0);
        assertEq(messagesCountOnlyTotal, 5);

        (IGroupChat.Message[] memory roundCountOnly, uint256 roundCountOnlyTotal) =
            chat.messagesByRound(groupId, 1, 0, 0, false);
        assertEq(roundCountOnly.length, 0);
        assertEq(roundCountOnlyTotal, 3);

        (IGroupChat.RoundSpan[] memory roundsCountOnly, uint256 roundsCountOnlyTotal) =
            chat.rounds(groupId, 0, 0, false);
        assertEq(roundsCountOnly.length, 0);
        assertEq(roundsCountOnlyTotal, 3);
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

        assertEq(messagesBySenderIdTotal(chat, groupId, senderId), 2);

        IGroupChat.Message[] memory senderMessages = messagesBySenderIdOf(chat, groupId, senderId, 0, 10, false);
        assertEq(senderMessages.length, 2);
        assertEq(senderMessages[0].messageId, 1);
        assertEq(senderMessages[1].messageId, 3);

        uint256[] memory messageIds = messageIdsBySenderIdOf(chat, groupId, senderId, 0, 10, false);
        assertEq(messageIds.length, 2);
        assertEq(messageIds[0], 1);
        assertEq(messageIds[1], 3);

        uint256[] memory reverseMessageIds = messageIdsBySenderIdOf(chat, groupId, senderId, 0, 10, true);
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

        assertEq(messagesBySenderIdTotal(chat, groupId, senderId), 2);
        assertEq(messagesBySenderIdOf(chat, groupId, senderId, 0, 10, false).length, 2);
        assertEq(messageIdsBySenderIdOf(chat, groupId, senderId, 0, 10, false).length, 2);

        assertEq(messagesBySenderIdTotal(chat, groupId, 999999), 0);
        assertEq(messagesBySenderIdOf(chat, groupId, 999999, 0, 10, false).length, 0);
        assertEq(messageIdsBySenderIdOf(chat, groupId, 999999, 0, 10, false).length, 0);
    }

    function testT063T068_senderEmptyViewsAndPaginationBoundaries() public {
        _activateEmpty();

        assertEq(messagesBySenderIdTotal(chat, groupId, 999), 0);
        assertEq(messagesBySenderIdOf(chat, groupId, 999, 0, 10, false).length, 0);
        assertEq(messageIdsBySenderIdOf(chat, groupId, 999, 0, 10, false).length, 0);
        assertEq(senderIdsTotal(chat, groupId), 0);
        assertEq(senderIdsOf(chat, groupId, 0, 0, false).length, 0);
        assertEq(senderIdsOf(chat, groupId, 99, 10, false).length, 0);
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

        assertEq(senderIdsTotal(chat, groupId), 2);

        uint256[] memory senders = senderIdsOf(chat, groupId, 0, 10, false);
        assertEq(senders.length, 2);
        assertEq(senders[0], senderId);
        assertEq(senders[1], otherGroupId);

        uint256[] memory reverseSenders = senderIdsOf(chat, groupId, 0, 10, true);
        assertEq(reverseSenders.length, 2);
        assertEq(reverseSenders[0], otherGroupId);
        assertEq(reverseSenders[1], senderId);
    }

    function testT083_messagePostedCarriesBodyQuoteAndMentionFlags() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.recordLogs();
        vm.prank(senderOwner);
        _post(groupId, senderId, "signal");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], MESSAGE_POSTED_SIG);
        assertEq(logs[0].topics[1], bytes32(groupId));
        assertEq(logs[0].topics[2], bytes32(uint256(1)));
        assertEq(logs[0].topics[3], bytes32(senderId));
        (
            address sender,
            uint256 round,
            uint256 quotedMessageId,
            bool hasQuote,
            bool mentionAll,
            uint256 mentionedSenderCount,
            string memory content
        ) = _decodeMessagePostedData(logs[0].data);
        assertEq(sender, senderOwner);
        assertEq(round, 1);
        assertEq(content, "signal");
        assertEq(quotedMessageId, 0);
        assertTrue(!hasQuote);
        assertTrue(!mentionAll);
        assertEq(mentionedSenderCount, 0);

        vm.recordLogs();
        vm.prank(senderOwner);
        _postWithQuote(groupId, senderId, "quoted", 1);
        logs = vm.getRecordedLogs();

        (,, quotedMessageId, hasQuote, mentionAll, mentionedSenderCount, content) =
            _decodeMessagePostedData(logs[0].data);
        assertEq(logs[0].topics[1], bytes32(groupId));
        assertEq(logs[0].topics[2], bytes32(uint256(2)));
        assertEq(content, "quoted");
        assertEq(quotedMessageId, 1);
        assertTrue(hasQuote);
        assertTrue(!mentionAll);
        assertEq(mentionedSenderCount, 0);
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

        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.MessageNotFound.selector, groupId, uint256(0)));
        chat.message(groupId, 0);

        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.MessageNotFound.selector, groupId, uint256(2)));
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
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.QuotedMessageNotFound.selector, groupId, uint256(4)));
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
