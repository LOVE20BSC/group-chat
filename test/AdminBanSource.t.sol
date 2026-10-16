// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupAdmin} from "../src/GroupAdmin.sol";

import {GroupBanList} from "../src/GroupBanList.sol";
import {IGroupAdmin} from "../src/interfaces/IGroupAdmin.sol";

import {IGroupBanList} from "../src/interfaces/IGroupBanList.sol";
import {IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {AdminBanSource} from "../src/sources/ban/AdminBanSource.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";

contract AdminBanSourceTest is GroupChatFixture {
    uint256 internal constant MAX_ADMIN_IDS = 20;

    GroupAdmin internal groupAdmin;
    GroupBanList internal banList;
    AdminBanSource internal banSource;
    address internal adminOwner = address(0xAD11);
    address internal secondAdminOwner = address(0xAD12);
    address internal stranger = address(0x5757);
    uint256 internal adminId;
    uint256 internal secondAdminId;

    function setUp() public override {
        super.setUp();
        adminId = groupNft.mint(adminOwner);
        secondAdminId = groupNft.mint(secondAdminOwner);
        groupAdmin = new GroupAdmin(address(groupDefaults), address(groupDelegate), MAX_ADMIN_IDS);
        banList = new GroupBanList(address(groupAdmin));
        banSource = new AdminBanSource(address(banList));
    }

    function testT120_ownerAndDelegateCanManageBanListsByDefault() public {
        address[] memory accounts = _addresses(senderOwner);

        vm.prank(chatOwner);
        banList.banBySenderAddresses(groupId, accounts);
        assertTrue(banList.isAddressBanned(groupId, senderOwner));

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateIdOwner);
        banList.banBySenderIds(groupId, _uints(senderId));
        assertTrue(banList.isSenderIdBanned(groupId, senderId));

        (bool[] memory addressBanned, address[] memory addressOperatorAddresses, uint256[] memory addressOperatorIds) =
            banList.addressBanDetails(groupId, accounts);
        assertTrue(addressBanned[0]);
        assertEq(addressOperatorAddresses[0], chatOwner);
        assertEq(addressOperatorIds[0], groupId);

        (bool[] memory senderIdBanned, address[] memory senderIdOperatorAddresses, uint256[] memory senderIdOperatorIds)
        = banList.senderIdBanDetails(groupId, _uints(senderId));
        assertTrue(senderIdBanned[0]);
        assertEq(senderIdOperatorAddresses[0], delegateIdOwner);
        assertEq(senderIdOperatorIds[0], delegateId);
    }

    function testT121_adminRequiresDefaultGroupAndCanOnlyManageBanLists() public {
        uint256[] memory admins = _uints(adminId);
        address[] memory accounts = _addresses(senderOwner);

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, admins);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));

        vm.prank(adminOwner);
        vm.expectRevert(IGroupBanList.UnauthorizedGroupBanListManager.selector);
        banList.banBySenderAddresses(groupId, accounts);

        vm.prank(adminOwner);
        groupDefaults.setDefaultGroupId(adminId);

        vm.prank(adminOwner);
        banList.banBySenderAddresses(groupId, accounts);
        assertTrue(banList.isAddressBanned(groupId, senderOwner));

        vm.prank(adminOwner);
        vm.expectRevert(IGroupAdmin.UnauthorizedGroupAdminManager.selector);
        groupAdmin.addAdmins(groupId, new uint256[](0));
    }

    function testT122_banSourceRejectsPostsAndUnbanRestoresPosting() public {
        _configureAdmin();
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(banSource), address(0), address(0));

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, _uints(senderId));

        (bool allowed, bytes4 reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(bytes32(reasonCode), bytes32(IGroupChatErrors.BanRejected.selector));

        vm.roll(originBlocks);
        vm.prank(senderOwner);
        vm.expectRevert(IGroupChatErrors.BanRejected.selector);
        _post(groupId, senderId, "banned");

        vm.prank(adminOwner);
        banList.unbanBySenderIds(groupId, _uints(senderId));

        assertTrue(!banList.isBanned(groupId, senderId, senderOwner));
        vm.prank(senderOwner);
        _post(groupId, senderId, "allowed");
        assertEq(chat.messagesCount(groupId), 1);
    }

    function testT123_listsAreIsolatedAndPaged() public {
        _configureAdmin();

        vm.prank(adminOwner);
        banList.banBySenderAddresses(groupId, _addresses(address(0x101), address(0x102), address(0x103)));
        assertEq(banList.addressBanListCount(groupId), 3);

        vm.prank(adminOwner);
        banList.banBySenderAddresses(groupId, _addresses(address(0x101)));

        (address[] memory page, address[] memory operatorAddresses, uint256[] memory operatorIds) =
            banList.addressBanList(groupId, 1, 2);
        assertEq(page.length, 2);
        assertEq(operatorAddresses.length, 2);
        assertEq(operatorIds.length, 2);
        assertEq(page[0], address(0x102));
        assertEq(page[1], address(0x103));
        assertEq(operatorAddresses[0], adminOwner);
        assertEq(operatorAddresses[1], adminOwner);
        assertEq(operatorIds[0], adminId);
        assertEq(operatorIds[1], adminId);

        (address[] memory empty, address[] memory emptyOperatorAddresses, uint256[] memory emptyOperatorIds) =
            banList.addressBanList(groupId, 99, 1);
        assertEq(empty.length, 0);
        assertEq(emptyOperatorAddresses.length, 0);
        assertEq(emptyOperatorIds.length, 0);
        assertEq(banList.addressBanListCount(otherGroupId), 0);

        vm.prank(adminOwner);
        banList.unbanBySenderAddresses(groupId, _addresses(address(0x102), address(0x999)));
        assertEq(banList.addressBanListCount(groupId), 2);
        assertTrue(!banList.isAddressBanned(groupId, address(0x102)));
    }

    function testT124_addRemoveAdminsValidateAndTransferInvalidatesAdmin() public {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId, secondAdminId));
        (uint256[] memory admins, bool[] memory isEffective) = groupAdmin.adminIds(groupId);
        assertEq(admins.length, 2);
        assertEq(admins[0], adminId);
        assertEq(admins[1], secondAdminId);
        assertEq(isEffective.length, 2);
        assertTrue(isEffective[0]);
        assertTrue(isEffective[1]);

        vm.prank(chatOwner);
        vm.expectRevert(IGroupAdmin.DuplicateAdminId.selector);
        groupAdmin.addAdmins(groupId, _uints(adminId, adminId));

        vm.prank(chatOwner);
        vm.expectRevert(IGroupAdmin.GroupNotExist.selector);
        groupAdmin.addAdmins(groupId, _uints(999999));

        vm.prank(adminOwner);
        groupDefaults.setDefaultGroupId(adminId);

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, _uints(senderId));
        assertTrue(banList.isSenderIdBanned(groupId, senderId));
        assertTrue(!banList.isAddressBanned(groupId, senderOwner));

        groupNft.transferFrom(adminOwner, stranger, adminId);
        (, bool[] memory invalidatedIsEffective) = groupAdmin.adminIds(groupId);
        assertTrue(!invalidatedIsEffective[0]);

        vm.prank(adminOwner);
        vm.expectRevert(IGroupBanList.UnauthorizedGroupBanListManager.selector);
        banList.banBySenderIds(groupId, _uints(otherGroupId));

        vm.prank(stranger);
        groupDefaults.setDefaultGroupId(adminId);

        vm.prank(stranger);
        vm.expectRevert(IGroupBanList.UnauthorizedGroupBanListManager.selector);
        banList.banBySenderIds(groupId, _uints(otherGroupId));

        groupNft.transferFrom(stranger, adminOwner, adminId);

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, _uints(otherGroupId));
        assertTrue(banList.isSenderIdBanned(groupId, otherGroupId));
    }

    function testT124B_addAdminsRejectsAdminCountAboveLimit() public {
        vm.expectRevert(IGroupAdmin.MaxAdminIdsZero.selector);
        new GroupAdmin(address(groupDefaults), address(groupDelegate), 0);

        uint256[] memory admins = new uint256[](MAX_ADMIN_IDS + 1);
        for (uint256 i = 0; i < admins.length; i++) {
            admins[i] = groupNft.mint(address(uint160(0xA000 + i)));
        }

        vm.prank(chatOwner);
        vm.expectRevert(IGroupAdmin.AdminIdsLimitExceeded.selector);
        groupAdmin.addAdmins(groupId, admins);
    }

    function testT125_senderIdBanListsOnlyAffectSenderIds() public {
        _configureAdmin();

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, _uints(senderId, otherGroupId));

        assertTrue(!banList.isAddressBanned(groupId, senderOwner));
        assertTrue(!banList.isAddressBanned(groupId, other));
        assertTrue(banList.isSenderIdBanned(groupId, senderId));
        assertTrue(banList.isSenderIdBanned(groupId, otherGroupId));
        assertTrue(banList.isBanned(groupId, senderId, senderOwner));
        assertTrue(banList.isBanned(groupId, otherGroupId, other));

        vm.prank(adminOwner);
        banList.unbanBySenderIds(groupId, _uints(senderId, otherGroupId));

        assertTrue(!banList.isAddressBanned(groupId, senderOwner));
        assertTrue(!banList.isAddressBanned(groupId, other));
        assertTrue(!banList.isSenderIdBanned(groupId, senderId));
        assertTrue(!banList.isSenderIdBanned(groupId, otherGroupId));
        assertTrue(!banList.isBanned(groupId, senderId, senderOwner));
        assertTrue(!banList.isBanned(groupId, otherGroupId, other));
    }

    function testT126_senderAddressBanListsOnlyAffectAddresses() public {
        _configureAdmin();

        vm.prank(senderOwner);
        groupDefaults.setDefaultGroupId(senderId);

        vm.prank(adminOwner);
        banList.banBySenderAddresses(groupId, _addresses(senderOwner, stranger));
        assertTrue(banList.isAddressBanned(groupId, senderOwner));
        assertTrue(!banList.isSenderIdBanned(groupId, senderId));
        assertTrue(banList.isAddressBanned(groupId, stranger));
        assertEq(banList.senderIdBanListCount(groupId), 0);

        vm.prank(adminOwner);
        banList.unbanBySenderAddresses(groupId, _addresses(senderOwner, stranger));
        assertTrue(!banList.isAddressBanned(groupId, senderOwner));
        assertTrue(!banList.isSenderIdBanned(groupId, senderId));
        assertTrue(!banList.isAddressBanned(groupId, stranger));
    }

    function testT126B_banBySendersAffectsAddressesAndSenderIdsTogether() public {
        _configureAdmin();

        vm.prank(stranger);
        vm.expectRevert(IGroupBanList.UnauthorizedGroupBanListManager.selector);
        banList.banBySenders(groupId, _uints(senderId), _addresses(senderOwner, other));

        vm.prank(adminOwner);
        vm.expectRevert(IGroupBanList.SenderPairLengthMismatch.selector);
        banList.banBySenders(groupId, _uints(senderId), _addresses(senderOwner, other));

        vm.prank(adminOwner);
        banList.banBySenders(groupId, _uints(senderId, otherGroupId), _addresses(senderOwner, other));

        assertTrue(banList.isAddressBanned(groupId, senderOwner));
        assertTrue(banList.isAddressBanned(groupId, other));
        assertTrue(banList.isSenderIdBanned(groupId, senderId));
        assertTrue(banList.isSenderIdBanned(groupId, otherGroupId));

        vm.prank(adminOwner);
        banList.unbanBySenders(groupId, _uints(senderId, otherGroupId), _addresses(senderOwner, other));

        assertTrue(!banList.isAddressBanned(groupId, senderOwner));
        assertTrue(!banList.isAddressBanned(groupId, other));
        assertTrue(!banList.isSenderIdBanned(groupId, senderId));
        assertTrue(!banList.isSenderIdBanned(groupId, otherGroupId));
    }

    function testT127_ownerCanManageBanListsWithoutDefaultGroupId() public {
        vm.prank(chatOwner);
        banList.banBySenderAddresses(groupId, _addresses(senderOwner));
        assertTrue(banList.isAddressBanned(groupId, senderOwner));

        (bool[] memory banned, address[] memory operatorAddresses, uint256[] memory operatorIds) =
            banList.addressBanDetails(groupId, _addresses(senderOwner));

        assertTrue(banned[0]);
        assertEq(operatorAddresses[0], chatOwner);
        assertEq(operatorIds[0], groupId);
    }

    function testT128_banDetailsReturnIndependentCacheSlicesAndOperators() public {
        _configureAdmin();

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, _uints(senderId));

        (bool[] memory addressBanned, address[] memory addressOperatorAddresses, uint256[] memory addressOperatorIds) =
            banList.addressBanDetails(groupId, _addresses(senderOwner, other));
        assertEq(addressBanned.length, 2);
        assertEq(addressOperatorAddresses.length, 2);
        assertEq(addressOperatorIds.length, 2);
        assertTrue(!addressBanned[0]);
        assertTrue(!addressBanned[1]);
        assertEq(addressOperatorAddresses[0], address(0));
        assertEq(addressOperatorAddresses[1], address(0));
        assertEq(addressOperatorIds[0], 0);
        assertEq(addressOperatorIds[1], 0);

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

        assertTrue(banList.isBanned(groupId, senderId, senderOwner));
    }

    function testT128B_banListPagesReturnCurrentListerAndClearOnUnban() public {
        _configureAdmin();

        vm.prank(adminOwner);
        banList.banBySenderAddresses(groupId, _addresses(senderOwner, other));

        (address[] memory addressPage, address[] memory operatorAddresses, uint256[] memory operatorIds) =
            banList.addressBanList(groupId, 0, 2);
        assertEq(addressPage.length, 2);
        assertEq(operatorAddresses.length, 2);
        assertEq(operatorIds.length, 2);
        assertEq(addressPage[0], senderOwner);
        assertEq(addressPage[1], other);
        assertEq(operatorAddresses[0], adminOwner);
        assertEq(operatorIds[0], adminId);
        assertEq(operatorAddresses[1], adminOwner);
        assertEq(operatorIds[1], adminId);

        vm.prank(adminOwner);
        banList.banBySenderIds(groupId, _uints(senderId, otherGroupId));

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
        groupAdmin.addAdmins(groupId, _uints(adminId, secondAdminId));

        vm.prank(secondAdminOwner);
        groupDefaults.setDefaultGroupId(secondAdminId);

        vm.prank(secondAdminOwner);
        banList.banBySenderAddresses(groupId, _addresses(other));

        (addressPage, operatorAddresses, operatorIds) = banList.addressBanList(groupId, 1, 1);
        assertEq(addressPage[0], other);
        assertEq(operatorAddresses[0], adminOwner);
        assertEq(operatorIds[0], adminId);

        vm.prank(adminOwner);
        banList.unbanBySenderAddresses(groupId, _addresses(senderOwner));

        vm.prank(secondAdminOwner);
        banList.banBySenderAddresses(groupId, _addresses(senderOwner));

        (addressPage, operatorAddresses, operatorIds) = banList.addressBanList(groupId, 0, 2);
        assertEq(addressPage.length, 2);
        _assertAddressPageOperator(addressPage, operatorAddresses, operatorIds, other, adminOwner, adminId);
        _assertAddressPageOperator(
            addressPage, operatorAddresses, operatorIds, senderOwner, secondAdminOwner, secondAdminId
        );
    }

    function _assertAddressPageOperator(
        address[] memory accounts,
        address[] memory operatorAddresses,
        uint256[] memory operatorIds,
        address account,
        address expectedOperatorAddress,
        uint256 expectedOperatorId
    ) internal pure {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == account) {
                assertEq(operatorAddresses[i], expectedOperatorAddress);
                assertEq(operatorIds[i], expectedOperatorId);
                return;
            }
        }
        assertTrue(false);
    }

    function _configureAdmin() internal {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId));

        vm.prank(adminOwner);
        groupDefaults.setDefaultGroupId(adminId);
    }

    function _addresses(address account) internal pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }

    function _addresses(address a, address b) internal pure returns (address[] memory accounts) {
        accounts = new address[](2);
        accounts[0] = a;
        accounts[1] = b;
    }

    function _addresses(address a, address b, address c) internal pure returns (address[] memory accounts) {
        accounts = new address[](3);
        accounts[0] = a;
        accounts[1] = b;
        accounts[2] = c;
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
