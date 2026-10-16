// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {MockGroupDefaults} from "./mocks/MockGroupDefaults.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract GroupChatDefaultSenderTest is GroupChatFixture {
    function testT087_setDefaultSenderAndPostAsDefaultSender() public {
        _activateEmpty();

        vm.recordLogs();
        vm.prank(senderOwner);
        groupDefaults.setDefaultGroupId(senderId);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], SET_DEFAULT_GROUP_ID_SIG);
        assertEq(groupDefaults.defaultGroupIdOf(senderOwner), senderId);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _postAsDefaultSender(groupId, "default-post");

        IGroupChat.Message memory fetched = chat.message(groupId, 1);
        assertEq(fetched.senderId, senderId);
        assertEq(fetched.senderAddress, senderOwner);
        assertEq(fetched.content, "default-post");
    }

    function testT088_defaultSenderInvalidatesOnTransferAndAutoRestores() public {
        vm.prank(senderOwner);
        groupDefaults.setDefaultGroupId(senderId);
        assertEq(groupDefaults.defaultGroupIdOf(senderOwner), senderId);

        vm.prank(senderOwner);
        groupNft.transferFrom(senderOwner, other, senderId);
        assertEq(groupDefaults.defaultGroupIdOf(senderOwner), 0);

        _activateEmpty();
        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.DefaultGroupIdNotSet.selector);
        _postAsDefaultSender(groupId, "stale");

        vm.prank(other);
        groupNft.transferFrom(other, senderOwner, senderId);
        assertEq(groupDefaults.defaultGroupIdOf(senderOwner), senderId);
    }

    function testT089_clearDefaultSenderUsesStoredValueEvenWhenInvalid() public {
        vm.prank(senderOwner);
        groupDefaults.setDefaultGroupId(senderId);

        vm.prank(senderOwner);
        groupNft.transferFrom(senderOwner, other, senderId);
        assertEq(groupDefaults.defaultGroupIdOf(senderOwner), 0);

        vm.recordLogs();
        vm.prank(senderOwner);
        groupDefaults.clearDefaultGroupId();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], CLEAR_DEFAULT_GROUP_ID_SIG);
        assertEq(groupDefaults.defaultGroupIdOf(senderOwner), 0);

        vm.prank(other);
        groupNft.transferFrom(other, senderOwner, senderId);
        assertEq(groupDefaults.defaultGroupIdOf(senderOwner), 0);
    }

    function testT090_defaultSenderSetAndClearRejectNoOpStates() public {
        vm.prank(senderOwner);
        vm.expectRevert(MockGroupDefaults.DefaultGroupIdNotSet.selector);
        groupDefaults.clearDefaultGroupId();

        vm.prank(senderOwner);
        groupDefaults.setDefaultGroupId(senderId);

        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(MockGroupDefaults.DefaultGroupIdAlreadySet.selector, senderId));
        groupDefaults.setDefaultGroupId(senderId);
    }
}
