// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../src/GroupAdmin.sol";

import {GroupChatBanList} from "../src/GroupChatBanList.sol";
import {GroupMember} from "../src/GroupMember.sol";
import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IGroupJoinScopeSourceErrors} from "../src/interfaces/sources/scope/IGroupJoinScopeSource.sol";
import {AdminBanSource} from "../src/sources/ban/AdminBanSource.sol";
import {GroupJoinScopeSource} from "../src/sources/scope/GroupJoinScopeSource.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";

contract MockGroupActionIndexes {
    mapping(uint256 => mapping(uint256 => bool)) public members;

    function setGroupMember(uint256 groupId, uint256 memberId, bool joined) external {
        members[groupId][memberId] = joined;
    }

    function isGroupMember(uint256 groupId, uint256 memberId) external view returns (bool) {
        return members[groupId][memberId];
    }
}

contract GroupJoinScopeSourceTest is GroupChatFixture {
    GroupAdmin internal groupAdmin;
    GroupMember internal member;
    MockGroupActionIndexes internal groupActionExecutor;
    GroupJoinScopeSource internal scope;

    function setUp() public override {
        super.setUp();
        groupAdmin = new GroupAdmin(address(groupDelegate), 20);
        member = new GroupMember(address(groupAdmin));
        groupActionExecutor = new MockGroupActionIndexes();
        scope = new GroupJoinScopeSource(address(member), address(groupActionExecutor));
    }

    function testT130_constructorRequiresGroupActionExecutorCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(IGroupJoinScopeSourceErrors.GroupActionExecutorNotContract.selector, address(0x1234))
        );
        new GroupJoinScopeSource(address(member), address(0x1234));

        vm.expectRevert(
            abi.encodeWithSelector(IGroupJoinScopeSourceErrors.GroupMemberNotContract.selector, address(0x1234))
        );
        new GroupJoinScopeSource(address(0x1234), address(groupActionExecutor));

        vm.expectRevert(
            abi.encodeWithSelector(IGroupJoinScopeSourceErrors.GroupMemberNotContract.selector, address(0))
        );
        new GroupJoinScopeSource(address(0), address(groupActionExecutor));

        vm.expectRevert(
            abi.encodeWithSelector(IGroupJoinScopeSourceErrors.GroupActionExecutorNotContract.selector, address(0))
        );
        new GroupJoinScopeSource(address(member), address(0));
    }

    function testT131_groupJoinParticipationControlsPost() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(0), address(0), address(0));

        (bool allowed, IGroupChat.PostRejectionReason reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.ScopeRejected);

        groupActionExecutor.setGroupMember(groupId, senderId, true);

        (allowed, reason) = _canPost(groupId, senderId);
        assertTrue(allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.None);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "joined-group");
        assertEq(chat.messagesCount(groupId), 1);

        groupActionExecutor.setGroupMember(groupId, senderId, false);

        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.ScopeRejected.selector, address(scope), groupId, senderId)
        );
        _post(groupId, senderId, "exited-group");
    }

    function testT131B_groupMemberScopeMembershipAlsoControlsPost() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(0), address(0), address(0));

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(groupId));

        vm.prank(chatOwner);
        member.addMemberIds(groupId, groupId, _uints(senderId));

        assertTrue(_canPostAllowed(groupId, senderId));

        groupNft.transferFrom(senderOwner, other, senderId);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotMemberOwner.selector, senderId));
        _post(groupId, senderId, "not-owner");

        vm.prank(other);
        _post(groupId, senderId, "new-owner");
        assertEq(chat.messagesCount(groupId), 1);
    }

    function testT132_groupJoinScopeCombinesWithAdminBanSource() public {
        GroupChatBanList banList = new GroupChatBanList(address(groupAdmin));
        AdminBanSource banSource = new AdminBanSource(address(banList));

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(banSource), address(0), address(0));

        groupActionExecutor.setGroupMember(groupId, senderId, true);

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(groupId));

        vm.prank(chatOwner);
        banList.banBySenderIds(groupId, groupId, _uints(senderId));

        (bool allowed, IGroupChat.PostRejectionReason reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.BanRejected);

        vm.prank(chatOwner);
        banList.unbanBySenderIds(groupId, groupId, _uints(senderId));

        assertTrue(_canPostAllowed(groupId, senderId));
    }

    function testT133_exposesMemberScopeAndGroupActionExecutorAddresses() public view {
        assertEq(scope.GROUP_MEMBER_ADDRESS(), address(member));
        assertEq(scope.GROUP_ACTION_EXECUTOR_ADDRESS(), address(groupActionExecutor));
        assertEq(member.GROUP_ADMIN_ADDRESS(), address(groupAdmin));
        assertEq(groupAdmin.MAX_ADMIN_IDS(), 20);
    }

    function _uints(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }
}
