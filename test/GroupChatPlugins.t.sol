// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

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
        chat.setPostingAllowed(groupId, groupId, false);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.PostingNotAllowed.selector, groupId));
        _post(groupId, senderId, "stopped");

        vm.prank(chatOwner);
        chat.setBeforePostPlugin(groupId, groupId, address(0));
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
        assertTrue(_canPostAllowed(groupId, senderId));

        scope.setAllowed(false);
        assertTrue(!_canPostAllowed(groupId, senderId));
        (bool allowed, IGroupChat.PostRejectionReason reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.ScopeRejected);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.ScopeRejected.selector, address(scope), groupId, senderId)
        );
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
        assertTrue(_canPostAllowed(groupId, senderId));

        banSource.setBanned(true);
        (bool allowed, IGroupChat.PostRejectionReason reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.BanRejected);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.BanRejected.selector, address(banSource), groupId, senderId)
        );
        _post(groupId, senderId, "banned-by-ban");

        banSource.setBanned(false);
        vm.prank(senderOwner);
        _post(groupId, senderId, "allowed-by-ban");
        assertEq(chat.messagesCount(groupId), 1);
    }

    function testT070C_canPostReturnsCoreAndSourceFailureReasons() public {
        (bool allowed, IGroupChat.PostRejectionReason reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.ChatNotActivated);

        (allowed, reason) = _canPost(999999, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.GroupNotExist);

        _activateEmpty();

        (allowed, reason) = _canPost(groupId, 999999);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.SenderNotExist);

        MockPostScopeFailSource failingScope = new MockPostScopeFailSource();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, groupId, address(failingScope));

        (allowed, reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.ScopeSourceFailed);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.ScopeSourceFailed.selector, address(failingScope))
        );
        _post(groupId, senderId, "scope-boom");

        vm.prank(chatOwner);
        chat.setScopeSource(groupId, groupId, address(0));

        MockPostBanFailSource failingBan = new MockPostBanFailSource();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, groupId, address(failingBan));

        (allowed, reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.BanSourceFailed);

        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.BanSourceFailed.selector, address(failingBan))
        );
        _post(groupId, senderId, "ban-boom");
    }

    function testT070D_scopeSetterPermissionsNoopStoppedStateAndEvents() public {
        MockPostScopeSource scope1 = new MockPostScopeSource();
        MockPostScopeSource scope2 = new MockPostScopeSource();

        _activateEmpty();

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, groupId));
        chat.setScopeSource(groupId, groupId, address(scope1));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        chat.setScopeSource(groupId, delegateId, address(scope1));
        Vm.Log[] memory scopeLogs1 = vm.getRecordedLogs();
        (address scopeOperator1, address prevScope1) = abi.decode(scopeLogs1[0].data, (address, address));
        assertEq(scopeLogs1.length, 1);
        assertEq(scopeLogs1[0].topics[0], SCOPE_SOURCE_CHANGED_SIG);
        assertEq(scopeLogs1[0].topics[1], bytes32(groupId));
        assertEq(scopeLogs1[0].topics[2], bytes32(uint256(uint160(address(scope1)))));
        assertEq(scopeLogs1[0].topics[3], bytes32(delegateId));
        assertEq(scopeOperator1, delegateIdOwner);
        assertEq(prevScope1, address(0));
        assertEq(chat.scopeSource(groupId), address(scope1));

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, groupId, address(scope1));
        Vm.Log[] memory sameScopeLogs = vm.getRecordedLogs();
        assertEq(sameScopeLogs.length, 0);

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, groupId, address(scope2));
        Vm.Log[] memory scopeLogs2 = vm.getRecordedLogs();
        (, address prevScope2) = abi.decode(scopeLogs2[0].data, (address, address));
        assertEq(prevScope2, address(scope1));

        vm.prank(chatOwner);
        chat.setScopeSource(groupId, groupId, address(0));

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, groupId, address(0));
        Vm.Log[] memory zeroScopeLogs = vm.getRecordedLogs();
        assertEq(zeroScopeLogs.length, 0);

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, false);

        vm.prank(chatOwner);
        chat.setScopeSource(groupId, groupId, address(scope1));
        assertEq(chat.scopeSource(groupId), address(scope1));
    }

    function testT070E_banSetterPermissionsNoopStoppedStateAndEvents() public {
        MockPostBanSource ban1 = new MockPostBanSource();
        MockPostBanSource ban2 = new MockPostBanSource();

        _activateEmpty();

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, groupId));
        chat.setBanSource(groupId, groupId, address(ban1));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        chat.setBanSource(groupId, delegateId, address(ban1));
        Vm.Log[] memory banLogs1 = vm.getRecordedLogs();
        (address banOperator1, address prevBan1) = abi.decode(banLogs1[0].data, (address, address));
        assertEq(banLogs1.length, 1);
        assertEq(banLogs1[0].topics[0], BAN_SOURCE_CHANGED_SIG);
        assertEq(banLogs1[0].topics[1], bytes32(groupId));
        assertEq(banLogs1[0].topics[2], bytes32(uint256(uint160(address(ban1)))));
        assertEq(banLogs1[0].topics[3], bytes32(delegateId));
        assertEq(banOperator1, delegateIdOwner);
        assertEq(prevBan1, address(0));
        assertEq(chat.banSource(groupId), address(ban1));

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, groupId, address(ban1));
        Vm.Log[] memory sameBanLogs = vm.getRecordedLogs();
        assertEq(sameBanLogs.length, 0);

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, groupId, address(ban2));
        Vm.Log[] memory banLogs2 = vm.getRecordedLogs();
        (, address prevBan2) = abi.decode(banLogs2[0].data, (address, address));
        assertEq(prevBan2, address(ban1));

        vm.prank(chatOwner);
        chat.setBanSource(groupId, groupId, address(0));

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, groupId, address(0));
        Vm.Log[] memory zeroBanLogs = vm.getRecordedLogs();
        assertEq(zeroBanLogs.length, 0);

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, false);

        vm.prank(chatOwner);
        chat.setBanSource(groupId, groupId, address(ban1));
        assertEq(chat.banSource(groupId), address(ban1));
    }

    function testT070F_activateChatEmitsInitialConfig() public {
        MockPostScopeSource scope = new MockPostScopeSource();
        MockPostBanSource banSource = new MockPostBanSource();
        MockBeforePostCapturePlugin beforePlugin = new MockBeforePostCapturePlugin();
        MockAfterPostCapturePlugin afterPlugin = new MockAfterPostCapturePlugin();

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(banSource), address(beforePlugin), address(afterPlugin));
        Vm.Log[] memory activateLogs = vm.getRecordedLogs();

        assertEq(activateLogs.length, 1);
        assertEq(activateLogs[0].topics[0], GROUP_CHAT_ACTIVATED_SIG);
        assertEq(activateLogs[0].topics[1], bytes32(groupId));
        assertEq(activateLogs[0].topics[2], bytes32(groupId));
        assertEq(activateLogs[0].topics[3], bytes32(uint256(uint160(chatOwner))));
        (
            bool postingAllowed,
            address activatedScope,
            address activatedBan,
            address activatedBefore,
            address activatedAfter
        ) = abi.decode(activateLogs[0].data, (bool, address, address, address, address));
        assertTrue(postingAllowed);
        assertEq(activatedScope, address(scope));
        assertEq(activatedBan, address(banSource));
        assertEq(activatedBefore, address(beforePlugin));
        assertEq(activatedAfter, address(afterPlugin));

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setScopeSource(groupId, groupId, address(0));
        Vm.Log[] memory scopeLogs = vm.getRecordedLogs();

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setBanSource(groupId, groupId, address(0));
        Vm.Log[] memory banLogs = vm.getRecordedLogs();

        assertEq(scopeLogs.length, 1);
        assertEq(scopeLogs[0].topics[0], SCOPE_SOURCE_CHANGED_SIG);
        assertEq(banLogs.length, 1);
        assertEq(banLogs[0].topics[0], BAN_SOURCE_CHANGED_SIG);
        (, address prevScope) = abi.decode(scopeLogs[0].data, (address, address));
        (, address prevBan) = abi.decode(banLogs[0].data, (address, address));
        assertEq(prevScope, address(scope));
        assertEq(prevBan, address(banSource));
    }

    function testT070F2_pluginSettersEmitChangedEvents() public {
        MockBeforePostCapturePlugin beforePlugin = new MockBeforePostCapturePlugin();
        MockAfterPostCapturePlugin afterPlugin = new MockAfterPostCapturePlugin();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(beforePlugin), address(afterPlugin));

        // The delegate operates the group, so `groupId` and `operatorId` stay distinguishable.
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        chat.setBeforePostPlugin(groupId, delegateId, address(0));
        Vm.Log[] memory beforePluginLogs = vm.getRecordedLogs();

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        chat.setAfterPostPlugin(groupId, delegateId, address(0));
        Vm.Log[] memory afterPluginLogs = vm.getRecordedLogs();

        assertEq(beforePluginLogs.length, 1);
        assertEq(beforePluginLogs[0].topics[0], BEFORE_POST_PLUGIN_CHANGED_SIG);
        assertEq(beforePluginLogs[0].topics[1], bytes32(groupId));
        assertEq(beforePluginLogs[0].topics[2], bytes32(uint256(0)));
        assertEq(beforePluginLogs[0].topics[3], bytes32(delegateId));
        assertEq(afterPluginLogs.length, 1);
        assertEq(afterPluginLogs[0].topics[0], AFTER_POST_PLUGIN_CHANGED_SIG);
        assertEq(afterPluginLogs[0].topics[1], bytes32(groupId));
        assertEq(afterPluginLogs[0].topics[2], bytes32(uint256(0)));
        assertEq(afterPluginLogs[0].topics[3], bytes32(delegateId));
        (address beforeOperator, address prevBeforePlugin) =
            abi.decode(beforePluginLogs[0].data, (address, address));
        (address afterOperator, address prevAfterPlugin) =
            abi.decode(afterPluginLogs[0].data, (address, address));
        assertEq(beforeOperator, delegateIdOwner);
        assertEq(afterOperator, delegateIdOwner);
        assertEq(prevBeforePlugin, address(beforePlugin));
        assertEq(prevAfterPlugin, address(afterPlugin));
    }

    function testT070G_ownerAndDelegateBypassScopeAndBanSources() public {
        MockPostScopeSource scope = new MockPostScopeSource();
        MockPostBanSource banSource = new MockPostBanSource();

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(banSource), address(0), address(0));

        scope.setAllowed(false);
        banSource.setBanned(true);

        (bool allowed, IGroupChat.PostRejectionReason reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.ScopeRejected);

        assertTrue(_canPostAllowed(groupId, groupId));

        vm.roll(originBlocks);
        vm.prank(chatOwner);
        _post(groupId, groupId, "owner-bypasses-sources");
        assertEq(chat.messagesCount(groupId), 1);

        scope.setAllowed(true);

        (allowed, reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.BanRejected);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        assertTrue(_canPostAllowed(groupId, delegateId));

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
        vm.expectRevert(abi.encodeWithSelector(MockBeforePostRejectPlugin.BeforePostRejected.selector));
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
        assertEq(logs[0].topics[0], MESSAGE_POSTED_SIG);
        assertEq(logs[0].topics[2], bytes32(uint256(1)));
        assertEq(logs[1].topics[0], AFTER_POST_PLUGIN_FAILED_SIG);
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
        assertEq(content, "ok");
        assertTrue(!hasQuote);
        assertTrue(!mentionAll);
        assertEq(quotedMessageId, 0);
        assertEq(mentionedSenderCount, 0);
        assertEq(_decodeFailAfterPostPluginRound(logs[1].data), 1);
        (, bytes32 errorHash, uint256 errorLength, bytes4 errorSelector) =
            abi.decode(logs[1].data, (uint256, bytes32, uint256, bytes4));
        assertEq(errorHash, keccak256(abi.encodeWithSelector(MockAfterPostFailPlugin.AfterPostFailed.selector)));
        assertEq(errorLength, 4);
        assertEq(errorSelector, MockAfterPostFailPlugin.AfterPostFailed.selector);
    }

    function testT073_pluginAddressWithoutCodeReverts() public {
        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.SourceNotContract.selector, other));
        chat.activateChat(groupId, other, address(0), address(0), address(0));

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.SourceNotContract.selector, other));
        chat.setScopeSource(groupId, groupId, other);

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.SourceNotContract.selector, other));
        chat.setBanSource(groupId, groupId, other);

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.PluginNotContract.selector, other));
        chat.setBeforePostPlugin(groupId, groupId, other);

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.PluginNotContract.selector, other));
        chat.setAfterPostPlugin(groupId, groupId, other);
    }

    function testT075_afterPostReenterIsBannedByNonReentrant() public {
        MockAfterPostReenterPlugin afterPlugin = new MockAfterPostReenterPlugin(address(chat), groupId, senderId);

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(afterPlugin));

        vm.roll(originBlocks);
        // A priming post keeps `groupId` and `messageId` from collapsing onto the same value.
        vm.prank(senderOwner);
        _post(groupId, senderId, "prime");
        vm.recordLogs();
        vm.prank(senderOwner);
        _post(groupId, senderId, "outer");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(chat.messagesCount(groupId), 2);
        assertEq(logs.length, 2);
        assertEq(logs[1].topics[0], AFTER_POST_PLUGIN_FAILED_SIG);
        assertEq(logs[1].topics[1], bytes32(groupId));
        assertEq(logs[1].topics[2], bytes32(uint256(2)));
        (, , , bytes4 errorSelector) = abi.decode(logs[1].data, (uint256, bytes32, uint256, bytes4));
        assertEq(errorSelector, IGroupChatErrors.Reentrant.selector);
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
        assertEq(logs[0].topics[0], MESSAGE_POSTED_SIG);
        assertEq(logs[1].topics[0], AFTER_POST_PLUGIN_FAILED_SIG);
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
        vm.expectRevert(abi.encodeWithSelector(MockBeforePostRejectMentionAllPlugin.MentionAllRejected.selector));
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
