// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupAdmin} from "../src/GroupAdmin.sol";

import {GroupBanList} from "../src/GroupBanList.sol";
import {GroupMember} from "../src/GroupMember.sol";
import {IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IGroupJoinScopeSource} from "../src/interfaces/sources/scope/IGroupJoinScopeSource.sol";
import {AdminBanSource} from "../src/sources/ban/AdminBanSource.sol";
import {GroupJoinScopeSource} from "../src/sources/scope/GroupJoinScopeSource.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";

contract MockGroupJoin {
    mapping(uint256 => mapping(address => uint256)) public counts;

    function setTokenAddressCount(uint256 groupId, address account, uint256 count) external {
        counts[groupId][account] = count;
    }

    function gTokenAddressesByGroupIdByAccountCount(uint256 groupId, address account) external view returns (uint256) {
        return counts[groupId][account];
    }
}

contract GroupJoinScopeSourceTest is GroupChatFixture {
    GroupAdmin internal groupAdmin;
    GroupMember internal member;
    MockGroupJoin internal groupJoin;
    GroupJoinScopeSource internal scope;

    function setUp() public override {
        super.setUp();
        groupAdmin = new GroupAdmin(address(groupDefaults), address(groupDelegate), 20);
        member = new GroupMember(address(groupAdmin));
        groupJoin = new MockGroupJoin();
        scope = new GroupJoinScopeSource(address(member), address(groupJoin));
    }

    function testT130_constructorRequiresGroupJoinCode() public {
        vm.expectRevert(IGroupJoinScopeSource.GroupJoinScopeSourceAddressHasNoCode.selector);
        new GroupJoinScopeSource(address(member), address(0x1234));

        vm.expectRevert(IGroupJoinScopeSource.GroupJoinScopeSourceAddressHasNoCode.selector);
        new GroupJoinScopeSource(address(0x1234), address(groupJoin));
    }

    function testT131_groupJoinParticipationControlsPost() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(0), address(0), address(0));

        (bool allowed, bytes4 reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.ScopeRejected.selector);

        groupJoin.setTokenAddressCount(groupId, senderOwner, 1);

        (allowed, reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(allowed);
        assertEq(reasonCode, bytes4(0));

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        _post(groupId, senderId, "joined-group");
        assertEq(chat.messagesCount(groupId), 1);

        groupJoin.setTokenAddressCount(groupId, senderOwner, 0);

        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.ScopeRejected.selector);
        _post(groupId, senderId, "exited-group");
    }

    function testT131B_groupMemberScopeMembershipAlsoControlsPost() public {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(0), address(0), address(0));

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(groupId));

        vm.prank(chatOwner);
        groupDefaults.setDefaultGroupId(groupId);

        vm.prank(chatOwner);
        member.addMemberIds(groupId, _uints(senderId));

        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));

        groupNft.transferFrom(senderOwner, other, senderId);

        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));
        assertTrue(_canPostAllowed(groupId, senderId, other));
    }

    function testT132_groupJoinScopeCombinesWithAdminBanSource() public {
        GroupBanList banList = new GroupBanList(address(groupAdmin));
        AdminBanSource banSource = new AdminBanSource(address(banList));

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(banSource), address(0), address(0));

        groupJoin.setTokenAddressCount(groupId, senderOwner, 1);

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(groupId));

        vm.prank(chatOwner);
        groupDefaults.setDefaultGroupId(groupId);

        vm.prank(chatOwner);
        banList.banBySenderIds(groupId, _uints(senderId));

        (bool allowed, bytes4 reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.BanRejected.selector);

        vm.prank(chatOwner);
        banList.unbanBySenderIds(groupId, _uints(senderId));

        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));
    }

    function testT133_exposesMemberScopeAndGroupJoinAddresses() public view {
        assertEq(scope.GROUP_MEMBER_ADDRESS(), address(member));
        assertEq(scope.GROUP_JOIN_ADDRESS(), address(groupJoin));
        assertEq(member.GROUP_ADMIN_ADDRESS(), address(groupAdmin));
        assertEq(groupAdmin.MAX_ADMIN_IDS(), 20);
    }

    function _uints(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }
}
