// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../src/GroupAdmin.sol";
import {GroupChat} from "../src/GroupChat.sol";
import {GroupChatDelegate} from "../src/GroupChatDelegate.sol";
import {IGroupChatDelegateErrors} from "../src/interfaces/IGroupChatDelegate.sol";
import {IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {MockLOVE20Group} from "./mocks/MockLOVE20Group.sol";
import {MockPostBanSource} from "./mocks/MockPlugins.sol";
import {MockPhase} from "./mocks/MockPhase.sol";
import {TestBase, Vm} from "./utils/TestBase.sol";

contract GroupChatDelegateTest is TestBase {
    MockLOVE20Group internal groupNft;
    GroupChatDelegate internal groupDelegate;

    address internal chatOwner = address(0xA11CE);
    address internal strangerOwner = address(0xB0B);
    address internal delegateOwner = address(0xD36E6A7E);

    uint256 internal groupId;
    uint256 internal strangerGroupId;
    uint256 internal delegateId;

    function setUp() public {
        groupNft = new MockLOVE20Group();
        groupId = groupNft.mint(chatOwner);
        strangerGroupId = groupNft.mint(strangerOwner);
        delegateId = groupNft.mint(delegateOwner);
        groupDelegate = new GroupChatDelegate(address(groupNft));
    }

    function testT140_setDelegateIdAndClearIt() public {
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        assertEq(groupDelegate.delegateIdOf(groupId), delegateId);
        assertEq(groupDelegate.delegatedGroupIdsCount(delegateId), 1);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        assertEq(groupDelegate.delegateIdOf(groupId), 0);
        assertEq(groupDelegate.delegatedGroupIdsCount(delegateId), 0);
    }

    function testT141_groupNftTransferInvalidatesDelegateAndTransferBackRestores() public {
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(chatOwner);
        groupNft.transferFrom(chatOwner, strangerOwner, groupId);
        assertEq(groupDelegate.delegateIdOf(groupId), 0);

        vm.prank(strangerOwner);
        groupNft.transferFrom(strangerOwner, chatOwner, groupId);
        assertEq(groupDelegate.delegateIdOf(groupId), delegateId);
    }

    function testT142_delegateNftTransferInvalidatesDelegateAndTransferBackRestores() public {
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateOwner);
        groupNft.transferFrom(delegateOwner, strangerOwner, delegateId);
        assertEq(groupDelegate.delegateIdOf(groupId), 0);

        vm.prank(strangerOwner);
        groupNft.transferFrom(strangerOwner, delegateOwner, delegateId);
        assertEq(groupDelegate.delegateIdOf(groupId), delegateId);
    }

    function testT143_delegatorWhitelistGatesSetDelegateId() public {
        vm.prank(delegateOwner);
        groupDelegate.setDelegatorWhitelistEnabled(delegateId, true);

        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatDelegateErrors.DelegatorGroupIdNotAllowed.selector);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId), true);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        assertEq(groupDelegate.delegateIdOf(groupId), delegateId);
    }

    function testT144_whitelistRemovalMakesResetOfSameIdNoOp() public {
        vm.prank(delegateOwner);
        groupDelegate.setDelegatorWhitelistEnabled(delegateId, true);
        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId), true);
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId), false);
        assertEq(groupDelegate.delegateIdOf(groupId), 0);

        vm.recordLogs();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        assertEq(groupDelegate.delegateIdOf(groupId), 0);
        assertEq(groupDelegate.delegatedGroupIdsCount(delegateId), 1);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function testT145_delegateOwnerClearsDelegatedGroupIdsInBatch() public {
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        vm.prank(strangerOwner);
        groupDelegate.setDelegateId(strangerGroupId, delegateId);

        vm.prank(delegateOwner);
        groupDelegate.clearDelegatedGroupIds(delegateId, _uints(groupId, strangerGroupId));

        assertEq(groupDelegate.delegateIdOf(groupId), 0);
        assertEq(groupDelegate.delegateIdOf(strangerGroupId), 0);
        assertEq(groupDelegate.delegatedGroupIdsCount(delegateId), 0);

        vm.prank(strangerOwner);
        vm.expectRevert(IGroupChatDelegateErrors.SenderNotDelegateOwner.selector);
        groupDelegate.clearDelegatedGroupIds(delegateId, _uints(groupId));
    }

    function testT146_delegateIdsOfAndCanSetDelegateTo() public {
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        uint256[] memory delegateIds = groupDelegate.delegateIdsOf(_uints(groupId, strangerGroupId));
        assertEq(delegateIds[0], delegateId);
        assertEq(delegateIds[1], 0);

        assertTrue(groupDelegate.canSetDelegateTo(strangerGroupId, 0));
        assertTrue(groupDelegate.canSetDelegateTo(strangerGroupId, delegateId));
        assertTrue(!groupDelegate.canSetDelegateTo(groupId, groupId));
        assertTrue(!groupDelegate.canSetDelegateTo(groupId, 999));
    }

    function testT146B_delegateQueriesReturnEmptyForMissingDelegate() public view {
        assertTrue(!groupDelegate.isDelegatorWhitelistEnabled(999));
        assertEq(groupDelegate.allowedDelegatorGroupIdsCount(999), 0);
        (uint256[] memory allowed, uint256 allowedTotal) = groupDelegate.allowedDelegatorGroupIds(999, 0, 10);
        assertEq(allowed.length, 0);
        assertEq(allowedTotal, 0);
        assertEq(groupDelegate.delegatedGroupIdsCount(999), 0);
        (uint256[] memory delegated, bool[] memory effective, uint256 delegatedTotal) =
            groupDelegate.delegatedGroupIds(999, 0, 10);
        assertEq(delegated.length, 0);
        assertEq(effective.length, 0);
        assertEq(delegatedTotal, 0);
        assertTrue(groupDelegate.canSetDelegateTo(groupId, 0));
    }

    function testT147_delegatedAndAllowedIndexesSwapPopOnRemoval() public {
        uint256 thirdGroupId = groupNft.mint(address(0xC0FFEE));
        uint256 fourthGroupId = groupNft.mint(address(0xD00D));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        vm.prank(strangerOwner);
        groupDelegate.setDelegateId(strangerGroupId, delegateId);
        vm.prank(address(0xC0FFEE));
        groupDelegate.setDelegateId(thirdGroupId, delegateId);
        vm.prank(address(0xD00D));
        groupDelegate.setDelegateId(fourthGroupId, delegateId);
        assertEq(groupDelegate.delegatedGroupIdsCount(delegateId), 4);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        assertEq(groupDelegate.delegatedGroupIdsCount(delegateId), 3);
        (uint256[] memory page,,) = groupDelegate.delegatedGroupIds(delegateId, 0, 10);
        assertEq(page.length, 3);

        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId, strangerGroupId, thirdGroupId), true);
        assertEq(groupDelegate.allowedDelegatorGroupIdsCount(delegateId), 3);

        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(strangerGroupId), false);
        assertEq(groupDelegate.allowedDelegatorGroupIdsCount(delegateId), 2);
        (uint256[] memory allowedPage,) = groupDelegate.allowedDelegatorGroupIds(delegateId, 0, 10);
        assertEq(allowedPage.length, 2);
    }

    function testT148_ownerOrDelegateIdOfReportsOwnerDelegateAndStranger() public {
        assertEq(groupDelegate.ownerOrDelegateIdOf(groupId, chatOwner), groupId);
        assertEq(groupDelegate.ownerOrDelegateIdOf(groupId, strangerOwner), 0);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        assertEq(groupDelegate.ownerOrDelegateIdOf(groupId, chatOwner), groupId);
        assertEq(groupDelegate.ownerOrDelegateIdOf(groupId, delegateOwner), delegateId);
        assertEq(groupDelegate.ownerOrDelegateIdOf(groupId, strangerOwner), 0);
    }

    function testT150_delegatedGroupIdsReportEffectiveFlag() public {
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        (uint256[] memory groups, bool[] memory effective, uint256 total) =
            groupDelegate.delegatedGroupIds(delegateId, 0, 10);
        assertEq(total, 1);
        assertEq(groups[0], groupId);
        assertEq(effective[0], true);

        groupNft.transferFrom(chatOwner, strangerOwner, groupId);
        (, effective, total) = groupDelegate.delegatedGroupIds(delegateId, 0, 10);
        assertEq(total, 1);
        assertEq(effective[0], false);

        groupNft.transferFrom(strangerOwner, chatOwner, groupId);
        (, effective,) = groupDelegate.delegatedGroupIds(delegateId, 0, 10);
        assertEq(effective[0], true);
    }

    function testT151_delegateWritesRejectNonOwnerAndSelf() public {
        vm.prank(strangerOwner);
        vm.expectRevert(IGroupChatDelegateErrors.SenderNotGroupOwner.selector);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatDelegateErrors.SenderNotDelegateOwner.selector);
        groupDelegate.setDelegatorWhitelistEnabled(delegateId, true);

        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatDelegateErrors.SenderNotDelegateOwner.selector);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId), true);

        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatDelegateErrors.DelegateIdCannotBeGroupId.selector);
        groupDelegate.setDelegateId(groupId, groupId);

        vm.prank(delegateOwner);
        vm.expectRevert(IGroupChatDelegateErrors.DelegateIdCannotBeGroupId.selector);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(delegateId), true);
    }

    function testT151B_delegateWritesRejectMissingDelegateId() public {
        vm.prank(chatOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999_999))
        );
        groupDelegate.setDelegatorWhitelistEnabled(999_999, true);
    }

    function testT151C_setDelegateIdRejectsMissingDelegateId() public {
        vm.prank(chatOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999_999))
        );
        groupDelegate.setDelegateId(groupId, 999_999);
    }

    function testT152_idempotentAndEmptyInputsAreNoop() public {
        vm.prank(delegateOwner);
        groupDelegate.setDelegatorWhitelistEnabled(delegateId, true);
        assertTrue(groupDelegate.isDelegatorWhitelistEnabled(delegateId));
        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.setDelegatorWhitelistEnabled(delegateId, true);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, new uint256[](0), true);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId), true);
        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId), true);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId), false);
        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId), false);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.prank(delegateOwner);
        groupDelegate.setAllowedDelegatorGroupIds(delegateId, _uints(groupId), true);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        vm.recordLogs();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        vm.recordLogs();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function testT153_delegationPaginationBoundaries() public {
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        (uint256[] memory page, uint256 total) = groupDelegate.allowedDelegatorGroupIds(delegateId, 0, 0);
        assertEq(page.length, 0);
        assertEq(total, 0);
        (page, total) = groupDelegate.allowedDelegatorGroupIds(delegateId, 5, 10);
        assertEq(page.length, 0);
        assertEq(total, 0);

        (uint256[] memory groups, bool[] memory effective, uint256 delegatedTotal) =
            groupDelegate.delegatedGroupIds(delegateId, 0, 0);
        assertEq(groups.length, 0);
        assertEq(effective.length, 0);
        assertEq(delegatedTotal, 1);

        (groups, effective, delegatedTotal) = groupDelegate.delegatedGroupIds(delegateId, 1, 10);
        assertEq(groups.length, 0);
        assertEq(effective.length, 0);
        assertEq(delegatedTotal, 1);

        uint256[] memory ids = groupDelegate.delegateIdsOf(new uint256[](0));
        assertEq(ids.length, 0);
    }

    function testT149_realDelegateAuthorizesMentionAllAndBypassesBanSource() public {
        MockPostBanSource banSource = new MockPostBanSource();
        banSource.setBanned(true);

        MockPhase phase = new MockPhase(block.number + 50, 100);
        GroupAdmin groupAdmin = new GroupAdmin(address(groupDelegate), 20);
        GroupChat chat = new GroupChat(address(groupAdmin), address(phase), 4096, 32);

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(banSource), address(0), address(0));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.roll(block.number + 50);
        assertTrue(_canPost(chat, groupId, delegateId));

        vm.prank(strangerOwner);
        vm.expectRevert(IGroupChatErrors.MentionAllUnauthorized.selector);
        chat.post(groupId, strangerGroupId, "stranger", _emptyMentions(), true, 0);

        vm.prank(strangerOwner);
        vm.expectRevert(IGroupChatErrors.BanRejected.selector);
        chat.post(groupId, strangerGroupId, "stranger", _emptyMentions(), false, 0);

        vm.prank(delegateOwner);
        chat.post(groupId, delegateId, "delegate", _emptyMentions(), true, 0);

        vm.prank(chatOwner);
        chat.post(groupId, groupId, "owner", _emptyMentions(), false, 0);

        assertEq(chat.messagesCount(groupId), 2);
    }

    function testT154_constructorAndMissingGroupReject() public {
        vm.expectRevert(IGroupChatDelegateErrors.InvalidAddress.selector);
        new GroupChatDelegate(address(0));

        vm.expectRevert(IGroupChatDelegateErrors.GroupNotExist.selector);
        groupDelegate.delegateIdOf(999);
    }

    function _canPost(GroupChat chat, uint256 groupId_, uint256 senderId_) internal view returns (bool) {
        (bool allowed,) = chat.canPost(groupId_, senderId_);
        return allowed;
    }

    function _emptyMentions() internal pure returns (uint256[] memory mentionedSenderIds) {
        mentionedSenderIds = new uint256[](0);
    }

    function _uints(uint256 a) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = a;
    }

    function _uints(uint256 a, uint256 b) internal pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = a;
        values[1] = b;
    }

    function _uints(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory values) {
        values = new uint256[](3);
        values[0] = a;
        values[1] = b;
        values[2] = c;
    }
}
