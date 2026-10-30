// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../src/GroupAdmin.sol";
import {GroupMember} from "../src/GroupMember.sol";
import {IGroupAdminErrors} from "../src/interfaces/IGroupAdmin.sol";
import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IGroupMemberErrors} from "../src/interfaces/IGroupMember.sol";
import {GroupMemberScope} from "../src/sources/scope/GroupMemberScope.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract GroupMemberScopeTest is GroupChatFixture {
    GroupAdmin internal groupAdmin;
    GroupMember internal member;
    GroupMemberScope internal scope;
    address internal adminOwner = address(0xAD11);
    uint256 internal adminId;

    function setUp() public override {
        super.setUp();
        adminId = groupNft.mint(adminOwner);
        groupAdmin = new GroupAdmin(address(groupDelegate), 20);
        member = new GroupMember(address(groupAdmin));
        scope = new GroupMemberScope(address(member));
    }

    function testT133A_constructorsStoreDependencies() public view {
        assertEq(member.GROUP_ADMIN_ADDRESS(), address(groupAdmin));
        assertEq(member.GROUP_ADDRESS(), address(groupNft));
        assertEq(scope.GROUP_MEMBER_ADDRESS(), address(member));
    }

    function testT133B_adminCanAddAndRemoveMemberIds() public {
        _configureAdmin();

        vm.prank(adminOwner);
        member.addMemberIds(groupId, adminId, _uints(senderId, otherGroupId));
        assertTrue(member.isMemberId(groupId, senderId));
        assertTrue(member.isMemberId(groupId, otherGroupId));
        assertEq(memberIdsTotal(member, groupId), 2);

        vm.prank(adminOwner);
        member.addMemberIds(groupId, adminId, _uints(senderId));

        uint256[] memory page = memberIdsOf(member, groupId, 1, 1, false);
        assertEq(page.length, 1);
        assertEq(page[0], otherGroupId);

        uint256[] memory reversePage = memberIdsOf(member, groupId, 0, 2, true);
        assertEq(reversePage.length, 2);
        assertEq(reversePage[0], otherGroupId);
        assertEq(reversePage[1], senderId);

        bool[] memory listed = member.isMemberIdBatch(groupId, _uints(senderId, groupId));
        assertTrue(listed[0]);
        assertTrue(!listed[1]);

        vm.prank(adminOwner);
        member.removeMemberIds(groupId, adminId, _uints(senderId));
        assertTrue(!member.isMemberId(groupId, senderId));
        assertTrue(member.isMemberId(groupId, otherGroupId));
    }

    function testT133B1_memberStatusChangedCarriesListed() public {
        _configureAdmin();

        vm.recordLogs();
        vm.prank(adminOwner);
        member.addMemberIds(groupId, adminId, _uints(senderId, otherGroupId));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 memberStatusChangedSig = keccak256("MemberStatusChanged(uint256,uint256,uint256,address,bool)");
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], memberStatusChangedSig);
        assertEq(logs[0].topics[1], bytes32(groupId));
        assertEq(logs[0].topics[2], bytes32(senderId));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(adminOwner))));
        (uint256 operatorId, bool listed) = abi.decode(logs[0].data, (uint256, bool));
        assertEq(operatorId, adminId);
        assertTrue(listed);
        assertEq(logs[1].topics[2], bytes32(otherGroupId));

        vm.recordLogs();
        vm.prank(adminOwner);
        member.removeMemberIds(groupId, adminId, _uints(senderId));
        logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], memberStatusChangedSig);
        (operatorId, listed) = abi.decode(logs[0].data, (uint256, bool));
        assertEq(operatorId, adminId);
        assertTrue(!listed);
    }

    function testT133B2_ownerAndDelegateCanManageMemberIds() public {
        vm.prank(chatOwner);
        member.addMemberIds(groupId, groupId, _uints(senderId));
        assertTrue(member.isMemberId(groupId, senderId));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateIdOwner);
        member.addMemberIds(groupId, delegateId, _uints(otherGroupId));
        assertTrue(member.isMemberId(groupId, otherGroupId));

        vm.prank(delegateIdOwner);
        member.removeMemberIds(groupId, delegateId, _uints(senderId));
        assertTrue(!member.isMemberId(groupId, senderId));
        assertTrue(member.isMemberId(groupId, otherGroupId));
    }

    function testT133C_memberIdsControlGroupChatPostAndTransferFollowsNft() public {
        _configureAdmin();
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(scope), address(0), address(0), address(0));

        (bool allowed, IGroupChat.PostRejectionReason reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.ScopeRejected);

        vm.prank(adminOwner);
        member.addMemberIds(groupId, adminId, _uints(senderId));

        assertTrue(_canPostAllowed(groupId, senderId));

        groupNft.transferFrom(senderOwner, other, senderId);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotMemberOwner.selector, senderId));
        _post(groupId, senderId, "not-owner");

        vm.prank(other);
        _post(groupId, senderId, "new-owner");
        assertEq(messagesTotal(chat, groupId), 1);
    }

    function testT133D_permissionsTargetsAndGroupIsolation() public {
        vm.prank(adminOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupMemberErrors.NotGroupOperator.selector, groupId, adminId));
        member.addMemberIds(groupId, adminId, _uints(senderId));

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId));

        vm.prank(adminOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(0)));
        member.addMemberIds(groupId, adminId, _uints(0));

        vm.prank(adminOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999999)));
        member.addMemberIds(groupId, adminId, _uints(999999));

        vm.prank(adminOwner);
        member.addMemberIds(groupId, adminId, _uints(senderId));

        assertTrue(member.isMemberId(groupId, senderId));
        assertTrue(!member.isMemberId(otherGroupId, senderId));

        vm.prank(adminOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupMemberErrors.NotGroupOperator.selector, otherGroupId, adminId));
        member.addMemberIds(otherGroupId, adminId, _uints(senderId));

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupAdminErrors.NotGroupOperator.selector, otherGroupId, groupId));
        groupAdmin.addAdmins(otherGroupId, groupId, _uints(adminId));
    }

    function _configureAdmin() internal {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId));
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
