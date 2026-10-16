// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupAdmin} from "../src/GroupAdmin.sol";
import {GroupMember} from "../src/GroupMember.sol";
import {IGroupAdmin} from "../src/interfaces/IGroupAdmin.sol";
import {IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IGroupMember} from "../src/interfaces/IGroupMember.sol";
import {IGroupMemberScope} from "../src/interfaces/sources/scope/IGroupMemberScope.sol";
import {GroupMemberScope} from "../src/sources/scope/GroupMemberScope.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";

contract GroupMemberScopeTest is GroupChatFixture {
    GroupAdmin internal groupAdmin;
    GroupMember internal member;
    GroupMemberScope internal scope;
    address internal adminOwner = address(0xAD11);
    uint256 internal adminId;

    function setUp() public override {
        super.setUp();
        adminId = groupNft.mint(adminOwner);
        groupAdmin = new GroupAdmin(address(groupDefaults), address(groupDelegate), 20);
        member = new GroupMember(address(groupAdmin));
        scope = new GroupMemberScope(address(member));
    }

    function testT133A_constructorsStoreDependenciesAndRejectNoCodeDependencies() public {
        assertEq(member.GROUP_ADMIN_ADDRESS(), address(groupAdmin));
        assertEq(member.GROUP_ADDRESS(), address(groupNft));
        assertEq(scope.GROUP_MEMBER_ADDRESS(), address(member));

        vm.expectRevert(IGroupMember.GroupMemberAddressHasNoCode.selector);
        new GroupMember(address(0x1234));

        vm.expectRevert(IGroupMemberScope.GroupMemberScopeAddressHasNoCode.selector);
        new GroupMemberScope(address(0x1234));
    }

    function testT133B_adminCanAddAndRemoveMemberIds() public {
        _configureAdmin();

        vm.prank(adminOwner);
        member.addMemberIds(groupId, _uints(senderId, otherGroupId));
        assertTrue(member.isMemberId(groupId, senderId));
        assertTrue(member.isMemberId(groupId, otherGroupId));
        assertEq(member.memberIdsCount(groupId), 2);

        vm.prank(adminOwner);
        member.addMemberIds(groupId, _uints(senderId));

        uint256[] memory page = member.memberIds(groupId, 1, 1);
        assertEq(page.length, 1);
        assertEq(page[0], otherGroupId);

        bool[] memory listed = member.isMemberIdBatch(groupId, _uints(senderId, groupId));
        assertTrue(listed[0]);
        assertTrue(!listed[1]);

        vm.prank(adminOwner);
        member.removeMemberIds(groupId, _uints(senderId));
        assertTrue(!member.isMemberId(groupId, senderId));
        assertTrue(member.isMemberId(groupId, otherGroupId));
    }

    function testT133B2_ownerAndDelegateCanManageMemberIdsByDefault() public {
        vm.prank(chatOwner);
        member.addMemberIds(groupId, _uints(senderId));
        assertTrue(member.isMemberId(groupId, senderId));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateIdOwner);
        member.addMemberIds(groupId, _uints(otherGroupId));
        assertTrue(member.isMemberId(groupId, otherGroupId));

        vm.prank(delegateIdOwner);
        member.removeMemberIds(groupId, _uints(senderId));
        assertTrue(!member.isMemberId(groupId, senderId));
        assertTrue(member.isMemberId(groupId, otherGroupId));
    }

    function testT133C_memberIdsControlGroupChatPostAndTransferFollowsNft() public {
        _configureAdmin();
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(0), address(0), address(0));

        (bool allowed, bytes4 reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(reasonCode, IGroupChatErrors.ScopeRejected.selector);

        vm.prank(adminOwner);
        member.addMemberIds(groupId, _uints(senderId));

        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));

        groupNft.transferFrom(senderOwner, other, senderId);

        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));
        assertTrue(_canPostAllowed(groupId, senderId, other));
    }

    function testT133D_permissionsTargetsAndGroupIsolation() public {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId));

        vm.prank(adminOwner);
        vm.expectRevert(IGroupMember.UnauthorizedGroupMemberManager.selector);
        member.addMemberIds(groupId, _uints(senderId));

        vm.prank(adminOwner);
        groupDefaults.setDefaultGroupId(adminId);

        vm.prank(adminOwner);
        vm.expectRevert(IGroupMember.TargetMemberIdZero.selector);
        member.addMemberIds(groupId, _uints(0));

        vm.prank(adminOwner);
        vm.expectRevert(IGroupMember.GroupNotExist.selector);
        member.addMemberIds(groupId, _uints(999999));

        vm.prank(adminOwner);
        member.addMemberIds(groupId, _uints(senderId));

        assertTrue(member.isMemberId(groupId, senderId));
        assertTrue(!member.isMemberId(otherGroupId, senderId));

        vm.prank(adminOwner);
        vm.expectRevert(IGroupMember.UnauthorizedGroupMemberManager.selector);
        member.addMemberIds(otherGroupId, _uints(senderId));

        vm.prank(chatOwner);
        vm.expectRevert(IGroupAdmin.UnauthorizedGroupAdminManager.selector);
        groupAdmin.addAdmins(otherGroupId, _uints(adminId));
    }

    function _configureAdmin() internal {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId));

        vm.prank(adminOwner);
        groupDefaults.setDefaultGroupId(adminId);
    }

    function _uints(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }

    function _uints(uint256 a, uint256 b) internal pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = a;
        values[1] = b;
    }
}
