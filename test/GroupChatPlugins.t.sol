// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {
    MockAfterPostCapturePlugin,
    MockAfterPostFailPlugin,
    MockAfterPostReenterPlugin,
    MockAfterPostSetPostingAllowedPlugin,
    MockBeforePostCapturePlugin,
    MockBeforePostRejectMentionAllPlugin,
    MockBeforePostRejectPlugin,
    MockManagedPlugin,
    MockPostBanFailSource,
    MockPostBanSource,
    MockPostScopeFailSource,
    MockPostScopeSource
} from "./mocks/MockPlugins.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract GroupChatPluginsTest is GroupChatFixture {
    function testT013T074_stoppedChatPreventsPostingButAllowsConfigWrites() public {
        MockManagedPlugin managedPlugin = new MockManagedPlugin(address(chat), address(groupDelegate));

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(managedPlugin), address(0));

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, false);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.PostingNotAllowed.selector);
        _post(groupId, senderId, "stopped");

        vm.prank(chatOwner);
        chat.setBeforePostPlugin(groupId, address(0));
        assertEq(chat.beforePostPlugin(groupId), address(0));

        vm.prank(chatOwner);
        managedPlugin.configure(groupId, bytes("owner-ok"));
        assertEq(managedPlugin.configValue(groupId), bytes("owner-ok"));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateIdOwner);
        managedPlugin.configure(groupId, bytes("delegate-ok"));
        assertEq(managedPlugin.configValue(groupId), bytes("delegate-ok"));
    }

    function testT070_crossGroupPostWithoutPluginIsAllowedByDefault() public {
        _activateEmpty();

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "default-open");

        assertEq(chat.messagesCount(groupId), 1);
    }

    function testT070A_scopeSourceControlsPostAndCanPost() public {
        MockPostScopeSource scope = new MockPostScopeSource();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(0), address(0), address(0));

        IGroupChat.ChatInfo memory info = chat.chatInfo(groupId);
        assertEq(info.scopeSource, address(scope));
        assertEq(info.banSource, address(0));
        assertEq(info.beforePostPlugin, address(0));
        assertEq(info.afterPostPlugin, address(0));
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));

        scope.setAllowed(false);
        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));
        (bool allowed, bytes4 reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.ScopeRejected.selector);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.ScopeRejected.selector);
        _post(groupId, senderId, "banned-by-scope");

        scope.setAllowed(true);
        vm.prank(senderOwner);
        _post(groupId, senderId, "allowed-by-scope");
        assertEq(chat.messagesCount(groupId), 1);
    }

    function testT070B_banSourceControlsPostAndCanPost() public {
        MockPostBanSource banSource = new MockPostBanSource();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(banSource), address(0), address(0));

        assertEq(chat.banSource(groupId), address(banSource));
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));

        banSource.setBanned(true);
        (bool allowed, bytes4 reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.BanRejected.selector);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.BanRejected.selector);
        _post(groupId, senderId, "banned-by-ban");

        banSource.setBanned(false);
        vm.prank(senderOwner);
        _post(groupId, senderId, "allowed-by-ban");
        assertEq(chat.messagesCount(groupId), 1);
    }

    function testT070C_canPostReturnsCoreAndSourceFailureReasons() public {
        (bool allowed, bytes4 reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.ChatNotActivated.selector);

        (allowed, reasonCode) = _canPost(999999, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.GroupNotExist.selector);

        _activateEmpty();

        (allowed, reasonCode) = _canPost(groupId, 999999, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.GroupNotExist.selector);

        (allowed, reasonCode) = _canPost(groupId, senderId, other);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.SenderAddressNotSenderIdOwner.selector);

        MockPostScopeFailSource failingScope = new MockPostScopeFailSource();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, address(failingScope));

        (allowed, reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.ScopeSourceFailed.selector);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.ScopeSourceFailed.selector);
        _post(groupId, senderId, "scope-boom");

        vm.prank(chatOwner);
        chat.setScopeSource(groupId, address(0));

        MockPostBanFailSource failingBan = new MockPostBanFailSource();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, address(failingBan));

        (allowed, reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.BanSourceFailed.selector);

        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.BanSourceFailed.selector);
        _post(groupId, senderId, "ban-boom");
    }

    function testT070D_scopeSetterPermissionsNoopStoppedStateAndEvents() public {
        MockPostScopeSource scope1 = new MockPostScopeSource();
        MockPostScopeSource scope2 = new MockPostScopeSource();

        _activateEmpty();

        vm.prank(other);
        vm.expectRevert(IGroupChatErrors.NotChatOwnerOrDelegateIdOwner.selector);
        chat.setScopeSource(groupId, address(scope1));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        chat.setScopeSource(groupId, address(scope1));
        Vm.Log[] memory scopeLogs1 = vm.getRecordedLogs();
        address prevScope1 = abi.decode(scopeLogs1[0].data, (address));
        assertEq(scopeLogs1.length, 1);
        assertEq(scopeLogs1[0].topics[0], SET_SCOPE_SOURCE_SIG);
        assertEq(prevScope1, address(0));
        assertEq(chat.scopeSource(groupId), address(scope1));

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, address(scope1));
        Vm.Log[] memory sameScopeLogs = vm.getRecordedLogs();
        assertEq(sameScopeLogs.length, 0);

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, address(scope2));
        Vm.Log[] memory scopeLogs2 = vm.getRecordedLogs();
        address prevScope2 = abi.decode(scopeLogs2[0].data, (address));
        assertEq(prevScope2, address(scope1));

        vm.prank(chatOwner);
        chat.setScopeSource(groupId, address(0));

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, address(0));
        Vm.Log[] memory zeroScopeLogs = vm.getRecordedLogs();
        assertEq(zeroScopeLogs.length, 0);

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, false);

        vm.prank(chatOwner);
        chat.setScopeSource(groupId, address(scope1));
        assertEq(chat.scopeSource(groupId), address(scope1));
    }

    function testT070E_banSetterPermissionsNoopStoppedStateAndEvents() public {
        MockPostBanSource ban1 = new MockPostBanSource();
        MockPostBanSource ban2 = new MockPostBanSource();

        _activateEmpty();

        vm.prank(other);
        vm.expectRevert(IGroupChatErrors.NotChatOwnerOrDelegateIdOwner.selector);
        chat.setBanSource(groupId, address(ban1));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        chat.setBanSource(groupId, address(ban1));
        Vm.Log[] memory banLogs1 = vm.getRecordedLogs();
        address prevBan1 = abi.decode(banLogs1[0].data, (address));
        assertEq(banLogs1.length, 1);
        assertEq(banLogs1[0].topics[0], SET_BAN_SOURCE_SIG);
        assertEq(prevBan1, address(0));
        assertEq(chat.banSource(groupId), address(ban1));

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, address(ban1));
        Vm.Log[] memory sameBanLogs = vm.getRecordedLogs();
        assertEq(sameBanLogs.length, 0);

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, address(ban2));
        Vm.Log[] memory banLogs2 = vm.getRecordedLogs();
        address prevBan2 = abi.decode(banLogs2[0].data, (address));
        assertEq(prevBan2, address(ban1));

        vm.prank(chatOwner);
        chat.setBanSource(groupId, address(0));

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, address(0));
        Vm.Log[] memory zeroBanLogs = vm.getRecordedLogs();
        assertEq(zeroBanLogs.length, 0);

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, false);

        vm.prank(chatOwner);
        chat.setBanSource(groupId, address(ban1));
        assertEq(chat.banSource(groupId), address(ban1));
    }

    function testT070F_activateChatEmitsSourceSlotDiffEvents() public {
        MockPostScopeSource scope = new MockPostScopeSource();
        MockPostBanSource banSource = new MockPostBanSource();

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(banSource), address(0), address(0));
        Vm.Log[] memory activateLogs = vm.getRecordedLogs();

        assertEq(activateLogs.length, 3);
        assertEq(activateLogs[0].topics[0], SET_SCOPE_SOURCE_SIG);
        assertEq(activateLogs[1].topics[0], SET_BAN_SOURCE_SIG);
        assertEq(activateLogs[2].topics[0], ACTIVATE_SIG);
        assertEq(_decodeAddress(activateLogs[0].data), address(0));
        assertEq(_decodeAddress(activateLogs[1].data), address(0));
        assertEq(activateLogs[2].data.length, 0);

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, address(0));
        Vm.Log[] memory scopeLogs = vm.getRecordedLogs();

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, address(0));
        Vm.Log[] memory banLogs = vm.getRecordedLogs();

        assertEq(scopeLogs.length, 1);
        assertEq(scopeLogs[0].topics[0], SET_SCOPE_SOURCE_SIG);
        assertEq(banLogs.length, 1);
        assertEq(banLogs[0].topics[0], SET_BAN_SOURCE_SIG);
        address prevScope = abi.decode(scopeLogs[0].data, (address));
        address prevBan = abi.decode(banLogs[0].data, (address));
        assertEq(prevScope, address(scope));
        assertEq(prevBan, address(banSource));
    }

    function testT070G_ownerAndDelegateBypassScopeAndBanSources() public {
        MockPostScopeSource scope = new MockPostScopeSource();
        MockPostBanSource banSource = new MockPostBanSource();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(banSource), address(0), address(0));

        scope.setAllowed(false);
        banSource.setBanned(true);

        (bool allowed, bytes4 reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.ScopeRejected.selector);

        (allowed, reasonCode) = _canPost(groupId, senderId, chatOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.SenderAddressNotSenderIdOwner.selector);

        assertTrue(_canPostAllowed(groupId, groupId, chatOwner));

        vm.roll(originBlocks);
        vm.prank(chatOwner);
        _post(groupId, groupId, "owner-bypasses-sources");
        assertEq(chat.messagesCount(groupId), 1);

        scope.setAllowed(true);

        (allowed, reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.BanRejected.selector);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        assertTrue(_canPostAllowed(groupId, delegateId, delegateIdOwner));

        vm.prank(delegateIdOwner);
        _post(groupId, delegateId, "delegate-bypasses-sources");
        assertEq(chat.messagesCount(groupId), 2);
    }

    function testT071_beforePostRejectRevertsWholePost() public {
        MockBeforePostRejectPlugin beforePlugin = new MockBeforePostRejectPlugin();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(beforePlugin), address(0));

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(MockBeforePostRejectPlugin.BeforePostRejected.selector);
        _post(groupId, senderId, "banned");

        assertEq(chat.messagesCount(groupId), 0);
    }

    function testT072_afterPostFailureDoesNotRollbackAndEventOrderIsCorrect() public {
        MockAfterPostFailPlugin afterPlugin = new MockAfterPostFailPlugin();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(afterPlugin));

        vm.roll(originBlocks);
        vm.recordLogs();
        vm.prank(senderOwner);
        _post(groupId, senderId, "ok");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(chat.messagesCount(groupId), 1);
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], POST_MESSAGE_SIG);
        assertEq(logs[1].topics[0], FAIL_AFTER_POST_PLUGIN_SIG);
        (uint256 round, uint256 messageId) = _decodePostMessage(logs[0].data);
        assertEq(round, 0);
        assertEq(messageId, 1);
        assertEq(_decodeFailAfterPostPluginRound(logs[1].data), 0);
    }

    function testT073_pluginAddressWithoutCodeReverts() public {
        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatErrors.SourceAddressHasNoCode.selector);
        chat.activateChat(groupId, other, address(0), address(0), address(0));

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatErrors.SourceAddressHasNoCode.selector);
        chat.setScopeSource(groupId, other);

        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatErrors.SourceAddressHasNoCode.selector);
        chat.setBanSource(groupId, other);

        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatErrors.PluginAddressHasNoCode.selector);
        chat.setBeforePostPlugin(groupId, other);

        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatErrors.PluginAddressHasNoCode.selector);
        chat.setAfterPostPlugin(groupId, other);
    }

    function testT075_afterPostReenterIsBannedByNonReentrant() public {
        MockAfterPostReenterPlugin afterPlugin = new MockAfterPostReenterPlugin(address(chat), groupId, senderId);

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(afterPlugin));

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "outer");

        assertEq(chat.messagesCount(groupId), 1);
    }

    function testT076_afterPostDelegateCannotMutateCoreState() public {
        MockAfterPostSetPostingAllowedPlugin afterPlugin = new MockAfterPostSetPostingAllowedPlugin(address(chat));

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(afterPlugin));

        vm.roll(originBlocks);
        vm.recordLogs();
        vm.prank(senderOwner);
        _post(groupId, senderId, "outer");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(chat.messagesCount(groupId), 1);
        assertTrue(chat.postingAllowed(groupId));
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], POST_MESSAGE_SIG);
        assertEq(logs[1].topics[0], FAIL_AFTER_POST_PLUGIN_SIG);
    }

    function testT077_beforePostPluginReceivesMentionArgs() public {
        MockBeforePostCapturePlugin beforePlugin = new MockBeforePostCapturePlugin();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(beforePlugin), address(0));

        uint256[] memory mentionedSenderIds = new uint256[](2);
        mentionedSenderIds[0] = otherGroupId;
        mentionedSenderIds[1] = delegateId;

        vm.roll(originBlocks);
        vm.prank(chatOwner);
        _postWithMentionedSenderIds(groupId, groupId, "@all hi", mentionedSenderIds, true);

        assertEq(beforePlugin.lastGroupId(), groupId);
        assertEq(beforePlugin.lastSenderId(), groupId);
        assertEq(beforePlugin.lastSenderAddress(), chatOwner);
        assertEq(beforePlugin.lastContent(), "@all hi");
        assertTrue(beforePlugin.lastMentionAll());

        uint256[] memory captured = beforePlugin.lastMentionedSenderIds();
        assertEq(captured.length, 2);
        assertEq(captured[0], otherGroupId);
        assertEq(captured[1], delegateId);
        assertEq(beforePlugin.lastQuotedMessageId(), 0);

        assertEq(chat.messagesCount(groupId), 1);
        assertTrue(chat.messages(groupId, 0, 1, false)[0].mentionAll);
    }

    function testT078_beforePostPluginCanJudgeMentionAll() public {
        MockBeforePostRejectMentionAllPlugin beforePlugin = new MockBeforePostRejectMentionAllPlugin();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(beforePlugin), address(0));

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "plain");

        vm.prank(chatOwner);
        vm.expectRevert(MockBeforePostRejectMentionAllPlugin.MentionAllRejected.selector);
        _postWithMentionedSenderIds(groupId, groupId, "@all", _emptyMentionedSenderIds(), true);

        assertEq(chat.messagesCount(groupId), 1);
        assertTrue(!chat.messages(groupId, 0, 1, false)[0].mentionAll);
    }

    function testT079_beforeAndAfterPostPluginsReceiveQuoteAndMessageContext() public {
        MockBeforePostCapturePlugin beforePlugin = new MockBeforePostCapturePlugin();
        MockAfterPostCapturePlugin afterPlugin = new MockAfterPostCapturePlugin();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(beforePlugin), address(afterPlugin));

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "base");

        vm.prank(senderOwner);
        _post(groupId, senderId, "base-1");

        uint256[] memory mentionedSenderIds = new uint256[](1);
        mentionedSenderIds[0] = otherGroupId;

        vm.prank(chatOwner);
        chat.post(groupId, groupId, "quoted", mentionedSenderIds, true, 1);

        assertEq(beforePlugin.lastQuotedMessageId(), 1);

        uint256[] memory beforeMentionedSenderIds = beforePlugin.lastMentionedSenderIds();
        assertEq(beforeMentionedSenderIds.length, 1);
        assertEq(beforeMentionedSenderIds[0], otherGroupId);

        assertEq(afterPlugin.lastGroupId(), groupId);
        assertEq(afterPlugin.lastSenderId(), groupId);
        assertEq(afterPlugin.lastSenderAddress(), chatOwner);
        assertEq(afterPlugin.lastContent(), "quoted");
        assertTrue(afterPlugin.lastMentionAll());
        assertEq(afterPlugin.lastQuotedMessageId(), 1);
        assertEq(afterPlugin.lastMessageId(), 3);
        assertEq(afterPlugin.lastBlockNumber(), block.number);
        assertEq(afterPlugin.lastTimestamp(), block.timestamp);

        uint256[] memory afterMentionedSenderIds = afterPlugin.lastMentionedSenderIds();
        assertEq(afterMentionedSenderIds.length, 1);
        assertEq(afterMentionedSenderIds[0], otherGroupId);
    }
}
