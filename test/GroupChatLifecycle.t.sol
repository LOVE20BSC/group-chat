// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract GroupChatLifecycleTest is GroupChatFixture {
    function testT001_constructorStoresConfigAndRoundNotStarted() public {
        assertEq(chat.GROUP_ADMIN_ADDRESS(), address(baseGroupAdmin));
        assertEq(chat.GROUP_ADDRESS(), address(groupNft));
        assertEq(chat.GROUP_DELEGATE_ADDRESS(), address(groupDelegate));
        assertEq(chat.PHASE_ADDRESS(), address(phase));
        assertEq(chat.MAX_CONTENT_LENGTH(), maxContentLength);
        assertEq(chat.MAX_MENTIONED_SENDER_IDS(), maxMentionedSenderIds);

        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.RoundNotStarted.selector, 1, 0));
        chat.currentRound();
    }

    function testT010_activateChat_requiresCurrentOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOwner.selector, groupId));
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));
    }

    function testT010C_postByOwnerBeforeActivationReportsChatNotActivated() public {
        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.ChatNotActivated.selector, groupId));
        _post(groupId, senderId, "not activated");
    }

    function testT010B_postAndSettersCheckAuthBeforeGroupState() public {
        // Not activated: sender auth wins over ChatNotActivated.
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotMemberOwner.selector, senderId));
        _post(groupId, senderId, "blocked");

        // Not activated: setter auth wins over ChatNotActivated.
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, groupId));
        chat.setScopeSource(groupId, groupId, address(0));

        // Activated but posting disabled: sender auth wins over PostingNotAllowed.
        _activateEmpty();
        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, false);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotMemberOwner.selector, senderId));
        _post(groupId, senderId, "blocked");
    }

    function testT011_activateChat_setsLiveStateAndFirstActivationSnapshot() public {
        _activateEmpty();

        IGroupChat.ChatInfo memory info = chat.chatInfo(groupId);
        assertEq(info.groupId, groupId);
        assertEq(info.owner, chatOwner);
        assertTrue(info.activated);
        assertTrue(info.postingAllowed);
        assertTrue(chat.isPostingAllowed(groupId));
        assertEq(info.scopeSource, address(0));
        assertEq(info.banSource, address(0));
        assertEq(info.beforePostPlugin, address(0));
        assertEq(info.afterPostPlugin, address(0));
        assertEq(info.firstActivatedOwner, chatOwner);
        assertEq(info.firstActivatedBlockNumber, block.number);
        assertEq(info.firstActivatedTimestamp, block.timestamp);

        assertEq(groupIdsTotal(chat), 1);

        uint256[] memory allChats = groupIdsOf(chat, 0, 10, false);
        assertEq(allChats.length, 1);
        assertEq(allChats[0], groupId);
    }

    function testT011B_chatInfosReturnsBatchInInputOrder() public {
        _activateEmpty();

        IGroupChat.ChatInfo[] memory infos = chat.chatInfosByGroupIds(_uints(groupId, senderId));
        assertEq(infos.length, 2);

        assertEq(infos[0].groupId, groupId);
        assertEq(infos[0].owner, chatOwner);
        assertTrue(infos[0].activated);
        assertTrue(infos[0].postingAllowed);
        assertEq(infos[0].firstActivatedOwner, chatOwner);

        assertEq(infos[1].groupId, senderId);
        assertEq(infos[1].owner, senderOwner);
        assertTrue(!infos[1].activated);
        assertTrue(!infos[1].postingAllowed);
        assertEq(infos[1].firstActivatedOwner, address(0));
    }

    function testT011C_chatInfosByGroupIdsRevertsOnMissingGroup() public {
        _activateEmpty();

        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.GroupNotExist.selector, uint256(999999)));
        chat.chatInfosByGroupIds(_uints(groupId, 999999));
    }

    function testT012_activateCannotRepeat() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.ChatAlreadyActivated.selector, groupId));
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        assertEq(groupIdsTotal(chat), 1);
    }

    function testT013_postingAllowedStopsAndResumesPostingOnly() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        IGroupChat.ChatInfo memory firstInfo = chat.chatInfo(groupId);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "old-message");

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, false);

        assertTrue(!chat.isPostingAllowed(groupId));
        assertTrue(!_canPostAllowed(groupId, senderId));
        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.PostingNotAllowed.selector, groupId));
        _post(groupId, senderId, "stopped");

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, true);
        assertTrue(chat.isPostingAllowed(groupId));

        IGroupChat.ChatInfo memory secondInfo = chat.chatInfo(groupId);
        assertEq(secondInfo.firstActivatedOwner, firstInfo.firstActivatedOwner);
        assertEq(secondInfo.firstActivatedBlockNumber, firstInfo.firstActivatedBlockNumber);
        assertEq(secondInfo.firstActivatedTimestamp, firstInfo.firstActivatedTimestamp);
        assertEq(messagesTotal(chat, groupId), 1);
        IGroupChat.Message[] memory fetched = messagesOf(chat, groupId, 0, 1, false);
        assertEq(fetched.length, 1);
        assertEq(fetched[0].content, "old-message");
        assertEq(fetched[0].mentionedSenderIds.length, 0);
        assertTrue(!fetched[0].mentionAll);
        assertEq(groupIdsTotal(chat), 1);

        vm.prank(senderOwner);
        _post(groupId, senderId, "resumed");
        assertEq(messagesTotal(chat, groupId), 2);
    }

    function testT014_postingAllowedPermissionsAndNoop() public {
        _activateEmpty();

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, groupId));
        chat.setPostingAllowed(groupId, groupId, false);

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, true);
        Vm.Log[] memory noopLogs = vm.getRecordedLogs();
        assertEq(noopLogs.length, 0);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        chat.setPostingAllowed(groupId, delegateId, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], POSTING_ALLOWED_CHANGED_SIG);
        assertEq(logs[0].topics[1], bytes32(groupId));
        assertEq(logs[0].topics[2], bytes32(delegateId));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(delegateIdOwner))));
        assertTrue(!abi.decode(logs[0].data, (bool)));
        IGroupChat.ChatInfo memory info = chat.chatInfo(groupId);
        assertTrue(!info.postingAllowed);
    }

    function testT015_managementWritesRejectNonexistentGroup() public {
        uint256 missingGroupId = 999_999;

        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.GroupNotExist.selector, missingGroupId));
        chat.setPostingAllowed(missingGroupId, missingGroupId, false);

        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.GroupNotExist.selector, missingGroupId));
        chat.setScopeSource(missingGroupId, missingGroupId, address(0));
    }

    function testT016_groupDiscoveryIndexesTrackActivatedChats() public {
        assertEq(groupIdsTotal(chat), 0);

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        vm.prank(senderOwner);
        chat.activateChat(senderId, address(0), address(0), address(0), address(0));

        uint256[] memory allChats = groupIdsOf(chat, 0, 10, false);
        assertEq(allChats.length, 2);
        assertEq(allChats[0], groupId);
        assertEq(allChats[1], senderId);

        uint256[] memory allChatsReverse = groupIdsOf(chat, 0, 10, true);
        assertEq(allChatsReverse.length, 2);
        assertEq(allChatsReverse[0], senderId);
        assertEq(allChatsReverse[1], groupId);

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, false);

        assertEq(groupIdsTotal(chat), 2);

        uint256[] memory allAfterStop = groupIdsOf(chat, 0, 10, false);
        assertEq(allAfterStop.length, 2);
        assertEq(allAfterStop[0], groupId);
        assertEq(allAfterStop[1], senderId);
    }

    function _uints(uint256 a, uint256 b) internal pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = a;
        values[1] = b;
    }
}
