// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupChat} from "../src/GroupChat.sol";
import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {MockGroupDelegate} from "./mocks/MockGroupDelegate.sol";
import {MockLOVE20Group} from "./mocks/MockLOVE20Group.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract MockGroupChatAdminConfig {
    address public immutable GROUP_DEFAULTS_ADDRESS;
    address public immutable GROUP_DELEGATE_ADDRESS;
    address public immutable GROUP_ADDRESS;

    constructor(address groupDefaults_, address groupDelegate_, address groupAddress_) {
        GROUP_DEFAULTS_ADDRESS = groupDefaults_;
        GROUP_DELEGATE_ADDRESS = groupDelegate_;
        GROUP_ADDRESS = groupAddress_;
    }
}

contract GroupChatLifecycleTest is GroupChatFixture {
    function testT001_constructorStoresConfigAndRoundNotStarted() public {
        assertEq(chat.GROUP_ADMIN_ADDRESS(), address(baseGroupAdmin));
        assertEq(chat.GROUP_ADDRESS(), address(groupNft));
        assertEq(chat.GROUP_DEFAULTS_ADDRESS(), address(groupDefaults));
        assertEq(chat.GROUP_DELEGATE_ADDRESS(), address(groupDelegate));
        assertEq(chat.originBlocks(), originBlocks);
        assertEq(chat.phaseBlocks(), phaseBlocks);
        assertEq(chat.MAX_CONTENT_LENGTH(), maxContentLength);
        assertEq(chat.MAX_MENTIONED_SENDER_IDS(), maxMentionedSenderIds);

        vm.expectRevert(IGroupChatErrors.RoundNotStarted.selector);
        chat.currentRound();
    }

    function testT002_constructorRejectsAdminWithoutCode() public {
        vm.expectRevert(IGroupChatErrors.GroupAdminHasNoCode.selector);
        new GroupChat(other, originBlocks, phaseBlocks, maxContentLength, maxMentionedSenderIds);
    }

    function testT002B_constructorRejectsDefaultsWithoutCode() public {
        MockGroupChatAdminConfig badAdmin =
            new MockGroupChatAdminConfig(other, address(groupDelegate), address(groupNft));

        vm.expectRevert(IGroupChatErrors.GroupDefaultsHasNoCode.selector);
        new GroupChat(address(badAdmin), originBlocks, phaseBlocks, maxContentLength, maxMentionedSenderIds);
    }

    function testT002C_constructorRejectsDelegateWithoutCode() public {
        MockGroupChatAdminConfig badAdmin =
            new MockGroupChatAdminConfig(address(groupDefaults), other, address(groupNft));

        vm.expectRevert(IGroupChatErrors.GroupDelegateHasNoCode.selector);
        new GroupChat(address(badAdmin), originBlocks, phaseBlocks, maxContentLength, maxMentionedSenderIds);
    }

    function testT002D_constructorRejectsDefaultsForDifferentGroup() public {
        MockLOVE20Group otherGroupNft = new MockLOVE20Group();
        MockGroupChatAdminConfig badAdmin =
            new MockGroupChatAdminConfig(address(groupDefaults), address(groupDelegate), address(otherGroupNft));

        vm.expectRevert(IGroupChatErrors.GroupDefaultsGroupMismatch.selector);
        new GroupChat(address(badAdmin), originBlocks, phaseBlocks, maxContentLength, maxMentionedSenderIds);
    }

    function testT002E_constructorRejectsDelegateForDifferentGroup() public {
        MockLOVE20Group otherGroupNft = new MockLOVE20Group();
        MockGroupDelegate otherGroupDelegate = new MockGroupDelegate(address(otherGroupNft));
        MockGroupChatAdminConfig badAdmin =
            new MockGroupChatAdminConfig(address(groupDefaults), address(otherGroupDelegate), address(groupNft));

        vm.expectRevert(IGroupChatErrors.GroupDelegateGroupMismatch.selector);
        new GroupChat(address(badAdmin), originBlocks, phaseBlocks, maxContentLength, maxMentionedSenderIds);
    }

    function testT003_constructorRejectsZeroPhaseBlocks() public {
        vm.expectRevert(IGroupChatErrors.PhaseBlocksZero.selector);
        new GroupChat(address(baseGroupAdmin), originBlocks, 0, maxContentLength, maxMentionedSenderIds);
    }

    function testT003B_constructorRejectsZeroMaxContentLength() public {
        vm.expectRevert(IGroupChatErrors.MaxContentLengthZero.selector);
        new GroupChat(address(baseGroupAdmin), originBlocks, phaseBlocks, 0, maxMentionedSenderIds);
    }

    function testT010_activateChat_requiresCurrentOwner() public {
        vm.prank(other);
        vm.expectRevert(IGroupChatErrors.NotChatOwner.selector);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));
    }

    function testT011_activateChat_setsLiveStateAndFirstActivationSnapshot() public {
        _activateEmpty();

        IGroupChat.ChatInfo memory info = chat.chatInfo(groupId);
        assertEq(info.groupId, groupId);
        assertEq(info.owner, chatOwner);
        assertTrue(info.activated);
        assertTrue(info.postingAllowed);
        assertTrue(chat.postingAllowed(groupId));
        assertEq(info.scopeSource, address(0));
        assertEq(info.banSource, address(0));
        assertEq(info.beforePostPlugin, address(0));
        assertEq(info.afterPostPlugin, address(0));
        assertEq(info.firstActivatedOwner, chatOwner);
        assertEq(info.firstActivatedBlockNumber, block.number);
        assertEq(info.firstActivatedTimestamp, block.timestamp);

        assertEq(chat.groupIdsCount(), 1);

        uint256[] memory allChats = chat.groupIds(0, 10, false);
        assertEq(allChats.length, 1);
        assertEq(allChats[0], groupId);
    }

    function testT011B_chatInfosReturnsBatchInInputOrder() public {
        _activateEmpty();

        IGroupChat.ChatInfo[] memory infos = chat.chatInfos(_uints(groupId, senderId));
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

    function testT012_activateCannotRepeat() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatErrors.ChatAlreadyActivated.selector);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        assertEq(chat.groupIdsCount(), 1);
    }

    function testT013_postingAllowedStopsAndResumesPostingOnly() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        IGroupChat.ChatInfo memory firstInfo = chat.chatInfo(groupId);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "old-message");

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, false);

        assertTrue(!chat.postingAllowed(groupId));
        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));
        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.PostingNotAllowed.selector);
        _post(groupId, senderId, "stopped");

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, true);
        assertTrue(chat.postingAllowed(groupId));

        IGroupChat.ChatInfo memory secondInfo = chat.chatInfo(groupId);
        assertEq(secondInfo.firstActivatedOwner, firstInfo.firstActivatedOwner);
        assertEq(secondInfo.firstActivatedBlockNumber, firstInfo.firstActivatedBlockNumber);
        assertEq(secondInfo.firstActivatedTimestamp, firstInfo.firstActivatedTimestamp);
        assertEq(chat.messagesCount(groupId), 1);
        IGroupChat.Message[] memory fetched = chat.messages(groupId, 0, 1, false);
        assertEq(fetched.length, 1);
        assertEq(fetched[0].content, "old-message");
        assertEq(fetched[0].mentionedSenderIds.length, 0);
        assertTrue(!fetched[0].mentionAll);
        assertEq(chat.groupIdsCount(), 1);

        vm.prank(senderOwner);
        _post(groupId, senderId, "resumed");
        assertEq(chat.messagesCount(groupId), 2);
    }

    function testT014_postingAllowedPermissionsAndNoop() public {
        _activateEmpty();

        vm.prank(other);
        vm.expectRevert(IGroupChatErrors.NotChatOwnerOrDelegateIdOwner.selector);
        chat.setPostingAllowed(groupId, false);

        vm.recordLogs();
        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, true);
        Vm.Log[] memory noopLogs = vm.getRecordedLogs();
        assertEq(noopLogs.length, 0);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        chat.setPostingAllowed(groupId, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], SET_POSTING_ALLOWED_SIG);
        IGroupChat.ChatInfo memory info = chat.chatInfo(groupId);
        assertTrue(!info.postingAllowed);
    }

    function testT015_managementWritesRejectNonexistentGroup() public {
        uint256 missingGroupId = 999_999;

        vm.expectRevert(IGroupChatErrors.GroupNotExist.selector);
        chat.setPostingAllowed(missingGroupId, false);

        vm.expectRevert(IGroupChatErrors.GroupNotExist.selector);
        chat.setScopeSource(missingGroupId, address(0));
    }

    function testT016_groupDiscoveryIndexesTrackActivatedChats() public {
        assertEq(chat.groupIdsCount(), 0);

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));

        vm.prank(senderOwner);
        chat.activateChat(senderId, address(0), address(0), address(0), address(0));

        uint256[] memory allChats = chat.groupIds(0, 10, false);
        assertEq(allChats.length, 2);
        assertEq(allChats[0], groupId);
        assertEq(allChats[1], senderId);

        uint256[] memory allChatsReverse = chat.groupIds(0, 10, true);
        assertEq(allChatsReverse.length, 2);
        assertEq(allChatsReverse[0], senderId);
        assertEq(allChatsReverse[1], groupId);

        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, false);

        assertEq(chat.groupIdsCount(), 2);

        uint256[] memory allAfterStop = chat.groupIds(0, 10, false);
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
