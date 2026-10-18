// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../src/GroupAdmin.sol";
import {GroupChatBanList} from "../src/GroupChatBanList.sol";
import {GroupMember} from "../src/GroupMember.sol";
import {IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IGroupAdmin} from "../src/interfaces/IGroupAdmin.sol";
import {IGroupChatBanList} from "../src/interfaces/IGroupChatBanList.sol";
import {IGroupMember} from "../src/interfaces/IGroupMember.sol";
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
        vm.expectRevert(IGroupChatErrors.NotChatOwnerOrDelegateIdOwner.selector);
        chat.setPostingAllowed(groupId, 0, false);
    }

    function testT201_zeroOperatorIdRejectedByGroupAdmin() public {
        vm.prank(other);
        vm.expectRevert(IGroupAdmin.UnauthorizedGroupAdminManager.selector);
        groupAdmin.addAdmins(groupId, 0, _uints(adminId));
    }

    function testT202_zeroOperatorIdRejectedByGroupMember() public {
        vm.prank(other);
        vm.expectRevert(IGroupMember.UnauthorizedGroupMemberManager.selector);
        member.addMemberIds(groupId, 0, _uints(senderId));
    }

    function testT203_zeroOperatorIdRejectedByBanList() public {
        vm.prank(other);
        vm.expectRevert(IGroupChatBanList.UnauthorizedGroupBanListManager.selector);
        banList.banBySenderIds(groupId, 0, _uints(senderId));
    }

    function testT204_wrongOperatorIdRejected() public {
        vm.prank(chatOwner);
        vm.expectRevert(IGroupChatErrors.NotChatOwnerOrDelegateIdOwner.selector);
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

    function _uints(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }
}
