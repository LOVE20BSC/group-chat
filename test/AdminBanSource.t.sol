// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../src/GroupAdmin.sol";
import {GroupChat} from "../src/GroupChat.sol";

import {GroupChatBanList} from "../src/GroupChatBanList.sol";
import {IGroupAdminErrors} from "../src/interfaces/IGroupAdmin.sol";

import {IGroupChatBanList} from "../src/interfaces/IGroupChatBanList.sol";
import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {AdminBanSource} from "../src/sources/ban/AdminBanSource.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract AdminBanSourceTest is GroupChatFixture {
    uint256 internal constant MAX_ADMIN_IDS = 20;

    GroupAdmin internal groupAdmin;
    GroupChatBanList internal banList;
    AdminBanSource internal banSource;
    address internal adminOwner = address(0xAD11);
    address internal secondAdminOwner = address(0xAD12);
    address internal stranger = address(0x5757);
    uint256 internal adminId;
    uint256 internal secondAdminId;
    bytes32 internal constant SENDER_BAN_CHANGED_SIG =
        keccak256("SenderBanChanged(uint256,uint256,uint256,address,bool)");

    function setUp() public override {
        super.setUp();
        adminId = groupNft.mint(adminOwner);
        secondAdminId = groupNft.mint(secondAdminOwner);
        groupAdmin = new GroupAdmin(address(groupDelegate), MAX_ADMIN_IDS);
        banList = new GroupChatBanList(address(groupAdmin));
        banSource = new AdminBanSource(address(banList));
    }

    function testT120_ownerAndDelegateCanManageBanLists() public {
        vm.prank(chatOwner);
        banList.banBySenderIds(groupId, groupId, _uints(senderId));
        assertTrue(banList.isSenderIdBanned(groupId, senderId));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateIdOwner);
        banList.banBySenderIds(groupId, delegateId, _uints(otherGroupId));

        (bool[] memory banned, address[] memory operatorAddresses, uint256[] memory operatorIds) =
            banList.senderIdBanDetails(groupId, _uints(senderId, otherGroupId));
        assertTrue(banned[0]);
        assertTrue(banned[1]);
        assertEq(operatorAddresses[0], chatOwner);
        assertEq(operatorIds[0], groupId);
        assertEq(operatorAddresses[1], delegateIdOwner);
        assertEq(operatorIds[1], delegateId);
    }

    function testT120B_senderBanChangedCarriesOperatorAndListed() public {
        // The delegate operates the group, so `groupId` and `operatorId` stay distinguishable.
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        banList.banBySenderIds(groupId, delegateId, _uints(senderId));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], SENDER_BAN_CHANGED_SIG);
        assertEq(logs[0].topics[1], bytes32(groupId));
        assertEq(logs[0].topics[2], bytes32(senderId));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(delegateIdOwner))));
        (uint256 operatorId, bool listed) = abi.decode(logs[0].data, (uint256, bool));
        assertEq(operatorId, delegateId);
        assertTrue(listed);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        banList.unbanBySenderIds(groupId, delegateId, _uints(senderId));
        logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], SENDER_BAN_CHANGED_SIG);
        (operatorId, listed) = abi.decode(logs[0].data, (uint256, bool));
        assertEq(operatorId, delegateId);
        assertTrue(!listed);
    }

    function testT121_adminRequiresExplicitAdminIdAndCanOnlyManageBanLists() public {
        uint256[] memory admins = _uints(adminId);

        vm.prank(adminOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, adminId));
        banList.banBySenderIds(groupId, adminId, _uints(senderId));

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, admins);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(senderId));
        assertTrue(banList.isSenderIdBanned(groupId, senderId));

        vm.prank(adminOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupAdminErrors.NotGroupOperator.selector, groupId, adminId));
        groupAdmin.addAdmins(groupId, adminId, new uint256[](0));
    }

    function testT121B_adminDoesNotBypassBanButOwnerSendingAsGroupDoes() public {
        GroupChat localChat = new GroupChat(address(groupAdmin), address(phase), maxContentLength, maxMentionedSenderIds);

        vm.prank(chatOwner);
        localChat.activateChat(groupId, address(0), address(banSource), address(0), address(0));

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId));
        assertTrue(groupAdmin.isAdminId(groupId, adminId));

        vm.prank(chatOwner);
        banList.banBySenderIds(groupId, groupId, _uints(adminId));
        assertTrue(banList.isSenderIdBanned(groupId, adminId));

        (bool allowed, IGroupChat.PostRejectionReason reason) = localChat.canPost(groupId, adminId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.BanRejected);

        vm.roll(originBlocks);
        vm.prank(adminOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.BanRejected.selector, groupId, adminId, address(banSource))
        );
        localChat.post(groupId, adminId, "admin", _emptyMentionedSenderIds(), false, 0);

        vm.prank(chatOwner);
        localChat.post(groupId, groupId, "owner", _emptyMentionedSenderIds(), false, 0);

        assertEq(localChat.messagesCount(groupId), 1);
    }

    function testT122_banSourceRejectsPostsAndUnbanRestoresPosting() public {
        _configureAdmin();
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(banSource), address(0), address(0));

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(senderId));

        (bool allowed, IGroupChat.PostRejectionReason reason) = _canPost(groupId, senderId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.BanRejected);

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.BanRejected.selector, groupId, senderId, address(banSource))
        );
        _post(groupId, senderId, "banned");

        vm.prank(adminOwner);
        banList.unbanBySenderIds(groupId, adminId, _uints(senderId));

        assertTrue(!banList.isSenderIdBanned(groupId, senderId));
        vm.prank(senderOwner);
        _post(groupId, senderId, "allowed");
        assertEq(chat.messagesCount(groupId), 1);
    }

    function testT123_banListsAreIsolatedAndPaged() public {
        _configureAdmin();

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(0x101, 0x102, 0x103));
        assertEq(banList.senderIdBanListCount(groupId), 3);

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(0x101));

        (uint256[] memory page, address[] memory operatorAddresses, uint256[] memory operatorIds) =
            banList.senderIdBanList(groupId, 1, 2);
        assertEq(page.length, 2);
        assertEq(operatorAddresses.length, 2);
        assertEq(operatorIds.length, 2);
        assertEq(page[0], 0x102);
        assertEq(page[1], 0x103);
        assertEq(operatorAddresses[0], adminOwner);
        assertEq(operatorAddresses[1], adminOwner);
        assertEq(operatorIds[0], adminId);
        assertEq(operatorIds[1], adminId);

        (uint256[] memory empty, address[] memory emptyOperatorAddresses, uint256[] memory emptyOperatorIds) =
            banList.senderIdBanList(groupId, 99, 1);
        assertEq(empty.length, 0);
        assertEq(emptyOperatorAddresses.length, 0);
        assertEq(emptyOperatorIds.length, 0);
        assertEq(banList.senderIdBanListCount(otherGroupId), 0);

        vm.prank(adminOwner);
        banList.unbanBySenderIds(groupId, adminId, _uints(0x102, 0x999));
        assertEq(banList.senderIdBanListCount(groupId), 2);
        assertTrue(!banList.isSenderIdBanned(groupId, 0x102));
    }

    function testT124_addRemoveAdminsValidateAndTransferInvalidatesAdmin() public {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId, secondAdminId));
        (uint256[] memory admins, bool[] memory isEffective) = groupAdmin.adminIds(groupId);
        assertEq(admins.length, 2);
        assertEq(admins[0], adminId);
        assertEq(admins[1], secondAdminId);
        assertEq(isEffective.length, 2);
        assertTrue(isEffective[0]);
        assertTrue(isEffective[1]);

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupAdminErrors.DuplicateMemberId.selector, adminId));
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId, adminId));

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999999)));
        groupAdmin.addAdmins(groupId, groupId, _uints(999999));

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(senderId));
        assertTrue(banList.isSenderIdBanned(groupId, senderId));

        groupNft.transferFrom(adminOwner, stranger, adminId);
        (, bool[] memory invalidatedIsEffective) = groupAdmin.adminIds(groupId);
        assertTrue(!invalidatedIsEffective[0]);

        vm.prank(adminOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, adminId));
        banList.banBySenderIds(groupId, adminId, _uints(otherGroupId));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, adminId));
        banList.banBySenderIds(groupId, adminId, _uints(otherGroupId));

        groupNft.transferFrom(stranger, adminOwner, adminId);

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(otherGroupId));
        assertTrue(banList.isSenderIdBanned(groupId, otherGroupId));
    }

    function testT124B_addAdminsRejectsAdminCountAboveLimit() public {
        uint256[] memory admins = new uint256[](MAX_ADMIN_IDS + 1);
        for (uint256 i = 0; i < admins.length; i++) {
            admins[i] = groupNft.mint(address(uint160(0xA000 + i)));
        }

        vm.prank(chatOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupAdminErrors.AdminIdsLimitExceeded.selector, groupId, MAX_ADMIN_IDS + 1, MAX_ADMIN_IDS)
        );
        groupAdmin.addAdmins(groupId, groupId, admins);
    }

    function testT125_senderIdBanListsOnlyAffectListedIds() public {
        _configureAdmin();

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(senderId, otherGroupId));

        assertTrue(banList.isSenderIdBanned(groupId, senderId));
        assertTrue(banList.isSenderIdBanned(groupId, otherGroupId));
        assertTrue(!banList.isSenderIdBanned(groupId, groupId));

        vm.prank(adminOwner);
        banList.unbanBySenderIds(groupId, adminId, _uints(senderId, otherGroupId));

        assertTrue(!banList.isSenderIdBanned(groupId, senderId));
        assertTrue(!banList.isSenderIdBanned(groupId, otherGroupId));
    }

    function testT127_ownerCanManageBanListsWithoutAdmin() public {
        vm.prank(chatOwner);
        banList.banBySenderIds(groupId, groupId, _uints(senderId));

        (bool[] memory banned, address[] memory operatorAddresses, uint256[] memory operatorIds) =
            banList.senderIdBanDetails(groupId, _uints(senderId));

        assertTrue(banned[0]);
        assertEq(operatorAddresses[0], chatOwner);
        assertEq(operatorIds[0], groupId);
    }

    function testT128_banDetailsReturnIndependentCacheSlicesAndOperators() public {
        _configureAdmin();

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(senderId));

        (bool[] memory senderIdBanned, address[] memory senderIdOperatorAddresses, uint256[] memory senderIdOperatorIds)
        = banList.senderIdBanDetails(groupId, _uints(senderId, otherGroupId));
        assertEq(senderIdBanned.length, 2);
        assertEq(senderIdOperatorAddresses.length, 2);
        assertEq(senderIdOperatorIds.length, 2);
        assertTrue(senderIdBanned[0]);
        assertTrue(!senderIdBanned[1]);
        assertEq(senderIdOperatorAddresses[0], adminOwner);
        assertEq(senderIdOperatorAddresses[1], address(0));
        assertEq(senderIdOperatorIds[0], adminId);
        assertEq(senderIdOperatorIds[1], 0);
    }

    function testT128B_banListPagesReturnCurrentListerAndClearOnUnban() public {
        _configureAdmin();

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(senderId, otherGroupId));

        (
            uint256[] memory senderIdPage,
            address[] memory senderIdPageOperatorAddresses,
            uint256[] memory senderIdPageOperatorIds
        ) = banList.senderIdBanList(groupId, 0, 2);
        assertEq(senderIdPage.length, 2);
        assertEq(senderIdPageOperatorAddresses.length, 2);
        assertEq(senderIdPageOperatorIds.length, 2);
        assertEq(senderIdPage[0], senderId);
        assertEq(senderIdPage[1], otherGroupId);
        assertEq(senderIdPageOperatorAddresses[0], adminOwner);
        assertEq(senderIdPageOperatorAddresses[1], adminOwner);
        assertEq(senderIdPageOperatorIds[0], adminId);
        assertEq(senderIdPageOperatorIds[1], adminId);

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId, secondAdminId));

        vm.prank(secondAdminOwner);
        banList.banBySenderIds(groupId, secondAdminId, _uints(otherGroupId));

        (senderIdPage, senderIdPageOperatorAddresses, senderIdPageOperatorIds) =
            banList.senderIdBanList(groupId, 1, 1);
        assertEq(senderIdPage[0], otherGroupId);
        assertEq(senderIdPageOperatorAddresses[0], adminOwner);
        assertEq(senderIdPageOperatorIds[0], adminId);

        vm.prank(adminOwner);
        banList.unbanBySenderIds(groupId, adminId, _uints(senderId));

        vm.prank(secondAdminOwner);
        banList.banBySenderIds(groupId, secondAdminId, _uints(senderId));

        (senderIdPage, senderIdPageOperatorAddresses, senderIdPageOperatorIds) =
            banList.senderIdBanList(groupId, 0, 2);
        assertEq(senderIdPage.length, 2);
        _assertPageOperator(senderIdPage, senderIdPageOperatorAddresses, senderIdPageOperatorIds, otherGroupId, adminOwner, adminId);
        _assertPageOperator(
            senderIdPage, senderIdPageOperatorAddresses, senderIdPageOperatorIds, senderId, secondAdminOwner, secondAdminId
        );
    }

    function testT129G_senderIdBannedBatchMatchesDetails() public {
        _configureAdmin();

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, adminId, _uints(senderId, otherGroupId));

        (bool[] memory banned,,) = banList.senderIdBanDetails(groupId, _uints(senderId, otherGroupId, groupId));
        bool[] memory batchBanned = banList.isSenderIdBannedBatch(groupId, _uints(senderId, otherGroupId, groupId));

        assertEq(batchBanned.length, 3);
        for (uint256 i = 0; i < batchBanned.length; i++) {
            assertEq(batchBanned[i], banned[i]);
        }
        assertTrue(batchBanned[0]);
        assertTrue(batchBanned[1]);
        assertTrue(!batchBanned[2]);

        vm.prank(adminOwner);
        banList.unbanBySenderIds(groupId, adminId, _uints(senderId));
        batchBanned = banList.isSenderIdBannedBatch(groupId, _uints(senderId, otherGroupId, groupId));
        assertTrue(!batchBanned[0]);
        assertTrue(batchBanned[1]);
        assertTrue(!batchBanned[2]);
    }

    function _assertPageOperator(
        uint256[] memory ids,
        address[] memory operatorAddresses,
        uint256[] memory operatorIds,
        uint256 id,
        address expectedOperatorAddress,
        uint256 expectedOperatorId
    ) internal pure {
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == id) {
                assertEq(operatorAddresses[i], expectedOperatorAddress);
                assertEq(operatorIds[i], expectedOperatorId);
                return;
            }
        }
        assertTrue(false);
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

    function _uints(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory values) {
        values = new uint256[](3);
        values[0] = a;
        values[1] = b;
        values[2] = c;
    }
}
