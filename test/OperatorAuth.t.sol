// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../src/GroupAdmin.sol";
import {GroupChatBanList} from "../src/GroupChatBanList.sol";
import {GroupMember} from "../src/GroupMember.sol";
import {IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IGroupAdmin} from "../src/interfaces/IGroupAdmin.sol";
import {IGroupChatBanList, IGroupChatBanListErrors} from "../src/interfaces/IGroupChatBanList.sol";
import {IGroupMember, IGroupMemberErrors} from "../src/interfaces/IGroupMember.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";

contract OperatorAuthTest is GroupChatFixture {
    GroupAdmin internal groupAdmin;
    GroupChatBanList internal banList;
    GroupMember internal member;
    address internal adminOwner = address(0xAD11);
    uint256 internal adminId;

    function setUp() public override {
        super.setUp();
        adminId = groupNft.mint(adminOwner);
        groupAdmin = new GroupAdmin(address(groupDelegate), 20);
        banList = new GroupChatBanList(address(groupAdmin));
        member = new GroupMember(address(groupAdmin));
        _activateEmpty();
    }

    function testT200_zeroOperatorIdRejectedByGroupChat() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, 0));
        chat.setPostingAllowed(groupId, 0, false);
    }

    function testT201_zeroOperatorIdRejectedByGroupAdmin() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, 0));
        groupAdmin.addAdmins(groupId, 0, _uints(adminId));
    }

    function testT202_zeroOperatorIdRejectedByGroupMember() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, 0));
        member.addMemberIds(groupId, 0, _uints(senderId));
    }

    function testT203_zeroOperatorIdRejectedByBanList() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, 0));
        banList.banBySenderIds(groupId, 0, _uints(senderId));
    }

    function testT204_wrongOperatorIdRejected() public {
        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, delegateId));
        chat.setPostingAllowed(groupId, delegateId, false);
    }

    function testT205_ownerAndDelegateIdsAccepted() public {
        vm.prank(chatOwner);
        chat.setPostingAllowed(groupId, groupId, false);
        assertTrue(!chat.postingAllowed(groupId));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateIdOwner);
        chat.setPostingAllowed(groupId, delegateId, true);
        assertTrue(chat.postingAllowed(groupId));
    }

    function testT206_duplicateMemberIdsRejected() public {
        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupMemberErrors.DuplicateMemberId.selector, senderId));
        member.addMemberIds(groupId, groupId, _uints(senderId, senderId));
    }

    function testT207_duplicateBanTargetsRejected() public {
        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatBanListErrors.DuplicateMemberId.selector, senderId));
        banList.banBySenderIds(groupId, groupId, _uints(senderId, senderId));
    }

    function testT208_zeroBanTargetRejected() public {
        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatBanListErrors.ZeroTargetSenderId.selector));
        banList.banBySenderIds(groupId, groupId, _uints(0));
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
