// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../src/GroupAdmin.sol";
import {IGroupAdminErrors} from "../src/interfaces/IGroupAdmin.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

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
    bytes32 internal constant ADMIN_CHANGED_SIG =
        keccak256("AdminChanged(uint256,uint256,uint256,address,bool,address,address,bool,address,address)");

    struct AdminChangedData {
        uint256 operatorId;
        bool listed;
        address groupOwnerSnapshot;
        address adminOwnerSnapshot;
        bool prevListed;
        address prevGroupOwnerSnapshot;
        address prevAdminOwnerSnapshot;
    }

    function setUp() public override {
        super.setUp();
        adminId = groupNft.mint(adminOwner);
        secondAdminId = groupNft.mint(secondAdminOwner);
        groupAdmin = new GroupAdmin(address(groupDelegate), MAX_ADMIN_IDS);
    }

    function testT129A_constructorStoresDependencies() public view {
        assertEq(groupAdmin.GROUP_DELEGATE_ADDRESS(), address(groupDelegate));
        assertEq(groupAdmin.GROUP_ADDRESS(), address(groupNft));
        assertEq(groupAdmin.MAX_ADMIN_IDS(), MAX_ADMIN_IDS);
    }

    function testT129B_ownerAndDelegateCanAddAndRemoveAdmins() public {
        vm.recordLogs();
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertAdminChangedLog(
            logs[0], groupId, chatOwner, adminId, groupId, true, false, chatOwner, adminOwner, address(0), address(0)
        );
        assertEq(logs.length, 1);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        groupAdmin.addAdmins(groupId, delegateId, _uints(secondAdminId));
        logs = vm.getRecordedLogs();
        _assertAdminChangedLog(
            logs[0],
            groupId,
            delegateIdOwner,
            secondAdminId,
            delegateId,
            true,
            false,
            chatOwner,
            secondAdminOwner,
            address(0),
            address(0)
        );
        assertEq(logs.length, 1);
        assertTrue(groupAdmin.isAdminId(groupId, adminId));
        assertTrue(groupAdmin.isAdminId(groupId, secondAdminId));

        vm.recordLogs();
        vm.prank(delegateIdOwner);
        groupAdmin.removeAdmins(groupId, delegateId, _uints(adminId));
        logs = vm.getRecordedLogs();
        _assertAdminChangedLog(
            logs[0], groupId, delegateIdOwner, adminId, delegateId, false, true, address(0), address(0), chatOwner, adminOwner
        );
        assertEq(logs.length, 1);
        assertTrue(!groupAdmin.isAdminId(groupId, adminId));
        assertTrue(groupAdmin.isAdminId(groupId, secondAdminId));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IGroupAdminErrors.NotGroupOperator.selector, groupId, groupId));
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IGroupAdminErrors.NotGroupOperator.selector, groupId, groupId));
        groupAdmin.removeAdmins(groupId, groupId, _uints(secondAdminId));
    }

    function testT129C_adminRequiresOwnerSnapshots() public {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId, secondAdminId));

        assertTrue(groupAdmin.isAdminId(groupId, adminId));

        groupNft.transferFrom(adminOwner, stranger, adminId);

        assertTrue(!groupAdmin.isAdminId(groupId, adminId));
        (uint256[] memory invalidatedAdminIds, bool[] memory invalidatedIsEffective) = groupAdmin.adminIds(groupId);
        assertEq(invalidatedAdminIds.length, 2);
        assertEq(invalidatedAdminIds[0], adminId);
        assertTrue(!invalidatedIsEffective[0]);

        groupNft.transferFrom(stranger, adminOwner, adminId);

        assertTrue(groupAdmin.isAdminId(groupId, adminId));
        (uint256[] memory restoredAdminIds, bool[] memory restoredIsEffective) = groupAdmin.adminIds(groupId);
        assertEq(restoredAdminIds.length, 2);
        assertEq(restoredAdminIds[0], adminId);
        assertTrue(restoredIsEffective[0]);
    }

    function testT129E_adminsInvalidateAndRestoreAcrossGroupOwnerTransfer() public {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId, secondAdminId));

        assertTrue(groupAdmin.isAdminId(groupId, adminId));
        assertTrue(groupAdmin.isAdminId(groupId, secondAdminId));

        groupNft.transferFrom(chatOwner, stranger, groupId);

        assertTrue(!groupAdmin.isAdminId(groupId, adminId));
        assertTrue(!groupAdmin.isAdminId(groupId, secondAdminId));

        vm.prank(stranger);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId));

        assertTrue(groupAdmin.isAdminId(groupId, adminId));
        assertTrue(!groupAdmin.isAdminId(groupId, secondAdminId));

        groupNft.transferFrom(stranger, chatOwner, groupId);

        assertTrue(!groupAdmin.isAdminId(groupId, adminId));
        assertTrue(groupAdmin.isAdminId(groupId, secondAdminId));
    }

    function testT129F_reapplyingSameAdminIdsUpdatesSnapshots() public {
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId));

        groupNft.transferFrom(adminOwner, stranger, adminId);
        assertTrue(!groupAdmin.isAdminId(groupId, adminId));

        vm.recordLogs();
        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertAdminChangedLog(
            logs[0], groupId, chatOwner, adminId, groupId, true, true, chatOwner, stranger, chatOwner, adminOwner
        );
        assertEq(logs.length, 1);

        assertTrue(groupAdmin.isAdminId(groupId, adminId));
    }

    function testT129D_addRemoveAdminsValidateInputLimitsAndList() public {
        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupAdminErrors.DuplicateMemberId.selector, adminId));
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId, adminId));

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(0)));
        groupAdmin.addAdmins(groupId, groupId, _uints(0));

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999999)));
        groupAdmin.addAdmins(groupId, groupId, _uints(999999));

        uint256[] memory admins = new uint256[](MAX_ADMIN_IDS + 1);
        for (uint256 i = 0; i < admins.length; i++) {
            admins[i] = groupNft.mint(address(uint160(0xA000 + i)));
        }

        vm.prank(chatOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupAdminErrors.AdminIdsLimitExceeded.selector, groupId, MAX_ADMIN_IDS + 1, MAX_ADMIN_IDS)
        );
        groupAdmin.addAdmins(groupId, groupId, admins);

        vm.prank(chatOwner);
        groupAdmin.addAdmins(groupId, groupId, _uints(adminId, secondAdminId));

        (uint256[] memory listed, bool[] memory isEffective) = groupAdmin.adminIds(groupId);
        assertEq(listed.length, 2);
        assertEq(listed[0], adminId);
        assertEq(listed[1], secondAdminId);
        assertEq(isEffective.length, 2);
        assertTrue(isEffective[0]);
        assertTrue(isEffective[1]);

        uint256 unlistedAdminId = groupNft.mint(address(0xAD13));
        vm.prank(chatOwner);
        groupAdmin.removeAdmins(groupId, groupId, _uints(adminId, unlistedAdminId));

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

    function _assertAdminChangedLog(
        Vm.Log memory log,
        uint256 groupId_,
        address operator,
        uint256 adminId_,
        uint256 operatorId,
        bool listed,
        bool prevListed,
        address groupOwnerSnapshot,
        address adminOwnerSnapshot,
        address prevGroupOwnerSnapshot,
        address prevAdminOwnerSnapshot
    ) internal view {
        assertEq(log.emitter, address(groupAdmin));
        assertEq(log.topics[0], ADMIN_CHANGED_SIG);
        assertEq(log.topics[1], bytes32(groupId_));
        assertEq(log.topics[2], bytes32(adminId_));
        assertEq(log.topics[3], bytes32(uint256(uint160(operator))));
        AdminChangedData memory decoded = abi.decode(log.data, (AdminChangedData));
        assertEq(decoded.operatorId, operatorId);
        assertEq(decoded.listed, listed);
        assertEq(decoded.prevListed, prevListed);
        assertEq(decoded.groupOwnerSnapshot, groupOwnerSnapshot);
        assertEq(decoded.adminOwnerSnapshot, adminOwnerSnapshot);
        assertEq(decoded.prevGroupOwnerSnapshot, prevGroupOwnerSnapshot);
        assertEq(decoded.prevAdminOwnerSnapshot, prevAdminOwnerSnapshot);
    }
}
