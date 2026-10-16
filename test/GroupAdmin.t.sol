// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupAdmin} from "../src/GroupAdmin.sol";
import {IGroupAdmin} from "../src/interfaces/IGroupAdmin.sol";
import {MockGroupDelegate} from "./mocks/MockGroupDelegate.sol";
import {MockLOVE20Group} from "./mocks/MockLOVE20Group.sol";

import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract GroupAdminTest is GroupChatFixture {
    uint256 internal constant MAX_ADMIN_IDS = 20;

    GroupAdmin internal groupAdmin;
    address internal adminOwner = address(0xAD11);
    address internal secondAdminOwner = address(0xAD12);
    address internal stranger = address(0x5757);
    uint256 internal adminId;
    uint256 internal secondAdminId;
    bytes32 internal constant SET_ADMIN_SIG = keccak256("SetAdmin(uint256,address,uint256,uint256,bool)");
    bytes32 internal constant SET_ADMIN_SNAPSHOT_SIG =
        keccak256("SetAdminSnapshot(uint256,address,uint256,uint256,address,address)");

    function setUp() public override {
        super.setUp();
        adminId = groupNft.mint(adminOwner);
        secondAdminId = groupNft.mint(secondAdminOwner);
        groupAdmin = new GroupAdmin(address(groupDefaults), address(groupDelegate), MAX_ADMIN_IDS);
    }

    function testT129A_constructorStoresDependenciesAndRejectsInvalidConfig() public {
        assertEq(groupAdmin.GROUP_DEFAULTS_ADDRESS(), address(groupDefaults));
        assertEq(groupAdmin.GROUP_DELEGATE_ADDRESS(), address(groupDelegate));
        assertEq(groupAdmin.GROUP_ADDRESS(), address(groupNft));
        assertEq(groupAdmin.MAX_ADMIN_IDS(), MAX_ADMIN_IDS);

        vm.expectRevert(IGroupAdmin.GroupAdminAddressHasNoCode.selector);
        new GroupAdmin(address(0x1234), address(groupDelegate), MAX_ADMIN_IDS);

        vm.expectRevert(IGroupAdmin.GroupAdminAddressHasNoCode.selector);
        new GroupAdmin(address(groupDefaults), address(0x1234), MAX_ADMIN_IDS);

        MockLOVE20Group otherGroup = new MockLOVE20Group();
        MockGroupDelegate mismatchedDelegate = new MockGroupDelegate(address(otherGroup));
        vm.expectRevert(IGroupAdmin.GroupDelegateGroupMismatch.selector);
        new GroupAdmin(address(groupDefaults), address(mismatchedDelegate), MAX_ADMIN_IDS);

        vm.expectRevert(IGroupAdmin.MaxAdminIdsZero.selector);
        new GroupAdmin(address(groupDefaults), address(groupDelegate), 0);
    }

    function testT129B_ownerAndDelegateCanAddAndRemoveAdmins() public {
        vm.recordLogs();
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertSetAdminSnapshotLog(logs[0], groupId, chatOwner, adminId, groupId, chatOwner, adminOwner);
        _assertSetAdminLog(logs[1], groupId, chatOwner, adminId, groupId, true);
        assertEq(logs.length, 2);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        groupAdmin.addAdmins(groupId, _uints(secondAdminId));
        logs = vm.getRecordedLogs();
        _assertSetAdminSnapshotLog(
            logs[0], groupId, delegateIdOwner, secondAdminId, delegateId, chatOwner, secondAdminOwner
        );
        _assertSetAdminLog(logs[1], groupId, delegateIdOwner, secondAdminId, delegateId, true);
        assertEq(logs.length, 2);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));
        assertTrue(groupAdmin.isAdminId(groupId, secondAdminId));

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        groupAdmin.removeAdmins(groupId, _uints(adminId));
        logs = vm.getRecordedLogs();
        _assertSetAdminLog(logs[0], groupId, delegateIdOwner, adminId, delegateId, false);
        assertEq(logs.length, 1);
        assertTrue(!groupAdmin.isAdminId(groupId, adminId));
        assertTrue(groupAdmin.isAdminId(groupId, secondAdminId));

        vm.prank(stranger);
        vm.expectRevert(IGroupAdmin.UnauthorizedGroupAdminManager.selector);
        groupAdmin.addAdmins(groupId, _uints(adminId));

        vm.prank(stranger);
        vm.expectRevert(IGroupAdmin.UnauthorizedGroupAdminManager.selector);
        groupAdmin.removeAdmins(groupId, _uints(secondAdminId));
    }

    function testT129C_adminIdOfRequiresConfiguredOwnerSnapshots() public {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId, secondAdminId));

        assertEq(groupAdmin.adminIdOf(groupId, adminOwner), 0);

        vm.prank(adminOwner);
        groupDefaults.setDefaultGroupId(adminId);
        assertEq(groupAdmin.adminIdOf(groupId, adminOwner), adminId);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));

        groupNft.transferFrom(adminOwner, stranger, adminId);

        assertEq(groupAdmin.adminIdOf(groupId, adminOwner), 0);
        assertTrue(!groupAdmin.isAdminId(groupId, adminId));
        (uint256[] memory invalidatedAdminIds, bool[] memory invalidatedIsEffective) = groupAdmin.adminIds(groupId);
        assertEq(invalidatedAdminIds.length, 2);
        assertEq(invalidatedAdminIds[0], adminId);
        assertTrue(!invalidatedIsEffective[0]);

        vm.prank(stranger);
        groupDefaults.setDefaultGroupId(adminId);
        assertEq(groupAdmin.adminIdOf(groupId, stranger), 0);

        groupNft.transferFrom(stranger, adminOwner, adminId);

        assertEq(groupAdmin.adminIdOf(groupId, adminOwner), adminId);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));
        assertEq(groupAdmin.adminIdOf(groupId, stranger), 0);
        (uint256[] memory restoredAdminIds, bool[] memory restoredIsEffective) = groupAdmin.adminIds(groupId);
        assertEq(restoredAdminIds.length, 2);
        assertEq(restoredAdminIds[0], adminId);
        assertTrue(restoredIsEffective[0]);
    }

    function testT129E_adminsInvalidateAndRestoreAcrossGroupOwnerTransfer() public {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId, secondAdminId));

        vm.prank(adminOwner);
        groupDefaults.setDefaultGroupId(adminId);
        vm.prank(secondAdminOwner);
        groupDefaults.setDefaultGroupId(secondAdminId);

        assertEq(groupAdmin.adminIdOf(groupId, adminOwner), adminId);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));
        assertEq(groupAdmin.adminIdOf(groupId, secondAdminOwner), secondAdminId);
        assertTrue(groupAdmin.isAdminId(groupId, secondAdminId));

        groupNft.transferFrom(chatOwner, stranger, groupId);

        assertEq(groupAdmin.adminIdOf(groupId, adminOwner), 0);
        assertTrue(!groupAdmin.isAdminId(groupId, adminId));
        assertEq(groupAdmin.adminIdOf(groupId, secondAdminOwner), 0);
        assertTrue(!groupAdmin.isAdminId(groupId, secondAdminId));

        vm.prank(stranger);
        groupAdmin.addAdmins(groupId, _uints(adminId));

        assertEq(groupAdmin.adminIdOf(groupId, adminOwner), adminId);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));
        assertEq(groupAdmin.adminIdOf(groupId, secondAdminOwner), 0);
        assertTrue(!groupAdmin.isAdminId(groupId, secondAdminId));

        groupNft.transferFrom(stranger, chatOwner, groupId);

        assertEq(groupAdmin.adminIdOf(groupId, adminOwner), 0);
        assertTrue(!groupAdmin.isAdminId(groupId, adminId));
        assertEq(groupAdmin.adminIdOf(groupId, secondAdminOwner), secondAdminId);
        assertTrue(groupAdmin.isAdminId(groupId, secondAdminId));
    }

    function testT129F_reapplyingSameAdminIdsUpdatesSnapshots() public {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId));

        vm.prank(adminOwner);
        groupDefaults.setDefaultGroupId(adminId);

        groupNft.transferFrom(adminOwner, stranger, adminId);
        assertEq(groupAdmin.adminIdOf(groupId, adminOwner), 0);

        vm.prank(stranger);
        groupDefaults.setDefaultGroupId(adminId);
        assertEq(groupAdmin.adminIdOf(groupId, stranger), 0);

        vm.recordLogs();
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertSetAdminSnapshotLog(logs[0], groupId, chatOwner, adminId, groupId, chatOwner, stranger);
        assertEq(logs.length, 1);

        assertEq(groupAdmin.adminIdOf(groupId, stranger), adminId);
    }

    function testT129D_addRemoveAdminsValidateInputLimitsAndList() public {
        vm.prank(chatOwner);
        vm.expectRevert(IGroupAdmin.DuplicateAdminId.selector);
        groupAdmin.addAdmins(groupId, _uints(adminId, adminId));

        vm.prank(chatOwner);
        vm.expectRevert(IGroupAdmin.GroupNotExist.selector);
        groupAdmin.addAdmins(groupId, _uints(999999));

        uint256[] memory admins = new uint256[](MAX_ADMIN_IDS + 1);
        for (uint256 i = 0; i < admins.length; i++) {
            admins[i] = groupNft.mint(address(uint160(0xA000 + i)));
        }

        vm.prank(chatOwner);
        vm.expectRevert(IGroupAdmin.AdminIdsLimitExceeded.selector);
        groupAdmin.addAdmins(groupId, admins);

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, _uints(adminId, secondAdminId));

        (uint256[] memory listed, bool[] memory isEffective) = groupAdmin.adminIds(groupId);
        assertEq(listed.length, 2);
        assertEq(listed[0], adminId);
        assertEq(listed[1], secondAdminId);
        assertEq(isEffective.length, 2);
        assertTrue(isEffective[0]);
        assertTrue(isEffective[1]);

        uint256 unlistedAdminId = groupNft.mint(address(0xAD13));
        vm.prank(chatOwner);
        groupAdmin.removeAdmins(groupId, _uints(adminId, unlistedAdminId));

        (uint256[] memory afterRemove, bool[] memory afterRemoveIsEffective) = groupAdmin.adminIds(groupId);
        assertEq(afterRemove.length, 1);
        assertEq(afterRemove[0], secondAdminId);
        assertEq(afterRemoveIsEffective.length, 1);
        assertTrue(afterRemoveIsEffective[0]);
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

    function _assertSetAdminSnapshotLog(
        Vm.Log memory log,
        uint256 groupId_,
        address operator,
        uint256 adminId_,
        uint256 operatorId,
        address groupOwnerSnapshot,
        address adminOwnerSnapshot
    ) internal view {
        assertEq(log.emitter, address(groupAdmin));
        assertEq(log.topics[0], SET_ADMIN_SNAPSHOT_SIG);
        assertEq(log.topics[1], bytes32(groupId_));
        assertEq(log.topics[2], bytes32(uint256(uint160(operator))));
        assertEq(log.topics[3], bytes32(adminId_));
        (uint256 decodedOperatorId, address decodedGroupOwnerSnapshot, address decodedAdminOwnerSnapshot) =
            abi.decode(log.data, (uint256, address, address));
        assertEq(decodedOperatorId, operatorId);
        assertEq(decodedGroupOwnerSnapshot, groupOwnerSnapshot);
        assertEq(decodedAdminOwnerSnapshot, adminOwnerSnapshot);
    }

    function _assertSetAdminLog(
        Vm.Log memory log,
        uint256 groupId_,
        address operator,
        uint256 adminId_,
        uint256 operatorId,
        bool listed
    ) internal view {
        assertEq(log.emitter, address(groupAdmin));
        assertEq(log.topics[0], SET_ADMIN_SIG);
        assertEq(log.topics[1], bytes32(groupId_));
        assertEq(log.topics[2], bytes32(uint256(uint160(operator))));
        assertEq(log.topics[3], bytes32(adminId_));
        (uint256 decodedOperatorId, bool decodedListed) = abi.decode(log.data, (uint256, bool));
        assertEq(decodedOperatorId, operatorId);
        assertEq(decodedListed, listed);
    }
}
