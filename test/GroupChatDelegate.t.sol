// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../src/GroupAdmin.sol";
import {GroupChat} from "../src/GroupChat.sol";
import {GroupChatDelegate} from "../src/GroupChatDelegate.sol";
import {IGroupChatDelegateErrors} from "../src/interfaces/IGroupChatDelegate.sol";
import {IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {MockLOVE20Group} from "./mocks/MockLOVE20Group.sol";
import {MockPostBanSource} from "./mocks/MockPlugins.sol";
import {MockPhase} from "./mocks/MockPhase.sol";
import {TestBase, Vm} from "./utils/TestBase.sol";

contract GroupChatDelegateTest is TestBase {
    MockLOVE20Group internal groupNft;
    GroupChatDelegate internal groupDelegate;

    address internal chatOwner = address(0xA11CE);
    address internal strangerOwner = address(0xB0B);
    address internal delegateOwner = address(0xD36E6A7E);

    uint256 internal groupId;
    uint256 internal strangerGroupId;
    uint256 internal delegateId;

    bytes32 internal constant DELEGATE_CHANGED_SIG =
        keccak256("DelegateChanged(uint256,uint256,address,address,address,uint256,address,address)");
    bytes32 internal constant DELEGATION_CLEARED_SIG =
        keccak256("DelegationCleared(uint256,uint256,address,address,address)");
    bytes32 internal constant DELEGATION_ACCEPTANCE_CHANGED_SIG =
        keccak256("DelegationAcceptanceChanged(uint256,address,bool)");

    function setUp() public {
        groupNft = new MockLOVE20Group();
        groupId = groupNft.mint(chatOwner);
        strangerGroupId = groupNft.mint(strangerOwner);
        delegateId = groupNft.mint(delegateOwner);
        groupDelegate = new GroupChatDelegate(address(groupNft));
    }

    function _acceptDelegations() internal {
        vm.prank(delegateOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, true);
    }

    function testT140_acceptanceDefaultsOffAndBlocksNewDelegation() public {
        assertTrue(!groupDelegate.isDelegationAcceptanceEnabled(delegateId));

        vm.prank(chatOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatDelegateErrors.DelegateNotAcceptingNewDelegations.selector, delegateId)
        );
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        assertEq(groupDelegate.effectiveDelegateId(groupId), 0);
        assertEq(delegatedGroupIdsTotal(groupDelegate, delegateId), 0);
    }

    function testT140B_setDelegateIdAndClearIt() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        assertEq(groupDelegate.effectiveDelegateId(groupId), delegateId);
        assertEq(delegatedGroupIdsTotal(groupDelegate, delegateId), 1);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        assertEq(groupDelegate.effectiveDelegateId(groupId), 0);
        assertEq(delegatedGroupIdsTotal(groupDelegate, delegateId), 0);
    }

    function testT140C_delegateChangedZeroIsExplicitClear() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.recordLogs();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], DELEGATE_CHANGED_SIG);
        assertEq(logs[0].topics[2], bytes32(0));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(chatOwner))));
        (
            address ownerSnapshot,
            address delegateOwnerSnapshot,
            uint256 prevDelegateId,
            address prevOwnerSnapshot,
            address prevDelegateOwnerSnapshot
        ) = abi.decode(logs[0].data, (address, address, uint256, address, address));
        assertEq(prevDelegateId, delegateId);
        assertEq(ownerSnapshot, address(0));
        assertEq(delegateOwnerSnapshot, address(0));
        assertEq(prevOwnerSnapshot, chatOwner);
        assertEq(prevDelegateOwnerSnapshot, delegateOwner);
    }

    function testT140D_delegateEventsCarryOwnerSnapshotOldAndNewValues() public {
        _acceptDelegations();
        vm.recordLogs();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], DELEGATE_CHANGED_SIG);
        assertEq(logs[0].topics[1], bytes32(groupId));
        assertEq(logs[0].topics[2], bytes32(delegateId));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(chatOwner))));
        (
            address ownerSnapshot,
            address delegateOwnerSnapshot,
            uint256 prevDelegateId,
            address prevOwnerSnapshot,
            address prevDelegateOwnerSnapshot
        ) = abi.decode(logs[0].data, (address, address, uint256, address, address));
        assertEq(prevDelegateId, 0);
        assertEq(ownerSnapshot, chatOwner);
        assertEq(delegateOwnerSnapshot, delegateOwner);
        assertEq(prevOwnerSnapshot, address(0));
        assertEq(prevDelegateOwnerSnapshot, address(0));

        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.clearDelegatedGroupIds(delegateId, _uints(groupId));
        logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], DELEGATION_CLEARED_SIG);
        assertEq(logs[0].topics[1], bytes32(groupId));
        assertEq(logs[0].topics[2], bytes32(delegateId));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(delegateOwner))));
        (address clearedPrevOwnerSnapshot, address clearedPrevDelegateOwnerSnapshot) =
            abi.decode(logs[0].data, (address, address));
        assertEq(clearedPrevOwnerSnapshot, chatOwner);
        assertEq(clearedPrevDelegateOwnerSnapshot, delegateOwner);
    }

    function testT141_groupNftTransferInvalidatesDelegateAndTransferBackRestores() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(chatOwner);
        groupNft.transferFrom(chatOwner, strangerOwner, groupId);
        assertEq(groupDelegate.effectiveDelegateId(groupId), 0);

        vm.prank(strangerOwner);
        groupNft.transferFrom(strangerOwner, chatOwner, groupId);
        assertEq(groupDelegate.effectiveDelegateId(groupId), delegateId);
    }

    function testT142_delegateNftTransferInvalidatesDelegateAndTransferBackRestores() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateOwner);
        groupNft.transferFrom(delegateOwner, strangerOwner, delegateId);
        assertEq(groupDelegate.effectiveDelegateId(groupId), 0);

        vm.prank(strangerOwner);
        groupNft.transferFrom(strangerOwner, delegateOwner, delegateId);
        assertEq(groupDelegate.effectiveDelegateId(groupId), delegateId);
    }

    function testT143_acceptanceSwitchGatesNewDesignationsOnly() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, false);

        assertEq(groupDelegate.effectiveDelegateId(groupId), delegateId);
        assertEq(groupDelegate.ownerOrDelegateId(groupId, delegateOwner), delegateId);
        (uint256[] memory delegatedGroups, bool[] memory effective, uint256 total) =
            groupDelegate.delegatedGroupIds(delegateId, 0, 10, false);
        assertEq(total, 1);
        assertEq(delegatedGroups[0], groupId);
        assertTrue(effective[0]);

        vm.prank(chatOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatDelegateErrors.DelegateNotAcceptingNewDelegations.selector, delegateId)
        );
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(strangerOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatDelegateErrors.DelegateNotAcceptingNewDelegations.selector, delegateId)
        );
        groupDelegate.setDelegateId(strangerGroupId, delegateId);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        assertEq(groupDelegate.effectiveDelegateId(groupId), 0);
    }

    function testT143B_acceptanceChangedEventCarriesFlags() public {
        assertTrue(!groupDelegate.isDelegationAcceptanceEnabled(delegateId));

        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], DELEGATION_ACCEPTANCE_CHANGED_SIG);
        assertEq(logs[0].topics[1], bytes32(delegateId));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(delegateOwner))));
        assertTrue(abi.decode(logs[0].data, (bool)));

        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, true);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, false);
        logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertTrue(!abi.decode(logs[0].data, (bool)));
        assertTrue(!groupDelegate.isDelegationAcceptanceEnabled(delegateId));
    }

    function testT143C_acceptanceSurvivesDelegateNftTransfer() public {
        _acceptDelegations();

        vm.prank(delegateOwner);
        groupNft.transferFrom(delegateOwner, strangerOwner, delegateId);

        // The switch belongs to the memberId, not to the holder.
        assertTrue(groupDelegate.isDelegationAcceptanceEnabled(delegateId));

        vm.prank(delegateOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatDelegateErrors.NotMemberOwner.selector, delegateId));
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, false);

        // Ineffective by snapshot, but re-designating the same id is a new designation and passes the switch.
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        assertEq(groupDelegate.effectiveDelegateId(groupId), delegateId);

        vm.prank(strangerOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, false);
        assertTrue(!groupDelegate.isDelegationAcceptanceEnabled(delegateId));
    }

    function testT143D_reDesignationAfterTransferNeedsAcceptance() public {
        _acceptDelegations();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateOwner);
        groupNft.transferFrom(delegateOwner, strangerOwner, delegateId);
        vm.prank(strangerOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, false);

        assertEq(groupDelegate.effectiveDelegateId(groupId), 0);

        vm.prank(chatOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatDelegateErrors.DelegateNotAcceptingNewDelegations.selector, delegateId)
        );
        groupDelegate.setDelegateId(groupId, delegateId);
    }

    function testT144_clearAfterDelegateNftTransferCarriesRawDelegateId() public {
        _acceptDelegations();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateOwner);
        groupNft.transferFrom(delegateOwner, strangerOwner, delegateId);
        assertEq(groupDelegate.effectiveDelegateId(groupId), 0);

        vm.prank(strangerOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, false);

        vm.recordLogs();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], DELEGATE_CHANGED_SIG);
        (
            address ownerSnapshot,
            address delegateOwnerSnapshot,
            uint256 prevDelegateId,
            address prevOwnerSnapshot,
            address prevDelegateOwnerSnapshot
        ) = abi.decode(logs[0].data, (address, address, uint256, address, address));
        // The whole prev group is the raw stored state, so the id agrees with the two snapshots.
        assertEq(prevDelegateId, delegateId);
        assertEq(prevOwnerSnapshot, chatOwner);
        assertEq(prevDelegateOwnerSnapshot, delegateOwner);
        assertEq(ownerSnapshot, address(0));
        assertEq(delegateOwnerSnapshot, address(0));
        assertEq(delegatedGroupIdsTotal(groupDelegate, delegateId), 0);
    }

    function testT145_delegateOwnerClearsDelegatedGroupIdsInBatch() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        vm.prank(strangerOwner);
        groupDelegate.setDelegateId(strangerGroupId, delegateId);

        vm.prank(delegateOwner);
        groupDelegate.clearDelegatedGroupIds(delegateId, _uints(groupId, strangerGroupId));

        assertEq(groupDelegate.effectiveDelegateId(groupId), 0);
        assertEq(groupDelegate.effectiveDelegateId(strangerGroupId), 0);
        assertEq(delegatedGroupIdsTotal(groupDelegate, delegateId), 0);

        vm.prank(strangerOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatDelegateErrors.NotMemberOwner.selector, delegateId));
        groupDelegate.clearDelegatedGroupIds(delegateId, _uints(groupId));
    }

    function testT146_effectiveDelegateIdsByGroupIdsReportPerGroup() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        uint256[] memory delegateIds = groupDelegate.effectiveDelegateIdsByGroupIds(_uints(groupId, strangerGroupId));
        assertEq(delegateIds[0], delegateId);
        assertEq(delegateIds[1], 0);
    }

    function testT146B_delegationQueriesReturnEmptyForMissingDelegate() public view {
        assertTrue(!groupDelegate.isDelegationAcceptanceEnabled(999));
        assertEq(delegatedGroupIdsTotal(groupDelegate, 999), 0);
        (uint256[] memory delegated, bool[] memory effective, uint256 delegatedTotal) =
            groupDelegate.delegatedGroupIds(999, 0, 10, false);
        assertEq(delegated.length, 0);
        assertEq(effective.length, 0);
        assertEq(delegatedTotal, 0);
    }

    function testT147_delegatedIndexesSwapPopOnRemoval() public {
        uint256 thirdGroupId = groupNft.mint(address(0xC0FFEE));
        uint256 fourthGroupId = groupNft.mint(address(0xD00D));

        _acceptDelegations();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        vm.prank(strangerOwner);
        groupDelegate.setDelegateId(strangerGroupId, delegateId);
        vm.prank(address(0xC0FFEE));
        groupDelegate.setDelegateId(thirdGroupId, delegateId);
        vm.prank(address(0xD00D));
        groupDelegate.setDelegateId(fourthGroupId, delegateId);
        assertEq(delegatedGroupIdsTotal(groupDelegate, delegateId), 4);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        assertEq(delegatedGroupIdsTotal(groupDelegate, delegateId), 3);
        (uint256[] memory page,,) = groupDelegate.delegatedGroupIds(delegateId, 0, 10, false);
        assertEq(page.length, 3);
    }

    function testT148_ownerOrDelegateIdReportsOwnerDelegateAndStranger() public {
        assertEq(groupDelegate.ownerOrDelegateId(groupId, chatOwner), groupId);
        assertEq(groupDelegate.ownerOrDelegateId(groupId, strangerOwner), 0);

        _acceptDelegations();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        assertEq(groupDelegate.ownerOrDelegateId(groupId, chatOwner), groupId);
        assertEq(groupDelegate.ownerOrDelegateId(groupId, delegateOwner), delegateId);
        assertEq(groupDelegate.ownerOrDelegateId(groupId, strangerOwner), 0);
    }

    function testT150_delegatedGroupIdsReportEffectiveFlag() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        (uint256[] memory groups, bool[] memory effective, uint256 total) =
            groupDelegate.delegatedGroupIds(delegateId, 0, 10, false);
        assertEq(total, 1);
        assertEq(groups[0], groupId);
        assertTrue(effective[0]);

        groupNft.transferFrom(chatOwner, strangerOwner, groupId);
        (, effective, total) = groupDelegate.delegatedGroupIds(delegateId, 0, 10, false);
        assertEq(total, 1);
        assertTrue(!effective[0]);

        groupNft.transferFrom(strangerOwner, chatOwner, groupId);
        (, effective,) = groupDelegate.delegatedGroupIds(delegateId, 0, 10, false);
        assertTrue(effective[0]);
    }

    function testT151_delegateWritesRejectNonOwnerAndSelf() public {
        vm.prank(strangerOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatDelegateErrors.NotGroupOwner.selector, groupId));
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatDelegateErrors.NotMemberOwner.selector, delegateId));
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, true);

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatDelegateErrors.DelegateIsSelfGroup.selector, groupId));
        groupDelegate.setDelegateId(groupId, groupId);
    }

    function testT151B_acceptanceSwitchRejectsMissingDelegateId() public {
        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999_999)));
        groupDelegate.setDelegationAcceptanceEnabled(999_999, true);
    }

    function testT151C_setDelegateIdRejectsMissingDelegateIdBeforeSwitch() public {
        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999_999)));
        groupDelegate.setDelegateId(groupId, 999_999);
    }

    function testT152_idempotentAndEmptyInputsAreNoop() public {
        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, false);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.clearDelegatedGroupIds(delegateId, new uint256[](0));
        assertEq(vm.getRecordedLogs().length, 0);

        _acceptDelegations();

        vm.recordLogs();
        vm.prank(delegateOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, true);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        vm.recordLogs();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        vm.recordLogs();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, 0);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function testT153_delegationPaginationBoundaries() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        (uint256[] memory groups, bool[] memory effective, uint256 delegatedTotal) =
            groupDelegate.delegatedGroupIds(delegateId, 0, 0, false);
        assertEq(groups.length, 0);
        assertEq(effective.length, 0);
        assertEq(delegatedTotal, 1);

        (groups, effective, delegatedTotal) = groupDelegate.delegatedGroupIds(delegateId, 1, 10, false);
        assertEq(groups.length, 0);
        assertEq(effective.length, 0);
        assertEq(delegatedTotal, 1);

        (groups, effective, delegatedTotal) = groupDelegate.delegatedGroupIds(delegateId, 0, 10, true);
        assertEq(groups.length, 1);
        assertEq(groups[0], groupId);
        assertTrue(effective[0]);
        assertEq(delegatedTotal, 1);

        uint256[] memory ids = groupDelegate.effectiveDelegateIdsByGroupIds(new uint256[](0));
        assertEq(ids.length, 0);
    }

    function testT149_realDelegateAuthorizesMentionAllAndBypassesBanSource() public {
        MockPostBanSource banSource = new MockPostBanSource();
        banSource.setBanned(true);

        MockPhase phase = new MockPhase(block.number + 50, 100);
        GroupAdmin groupAdmin = new GroupAdmin(address(groupDelegate), 20);
        GroupChat chat = new GroupChat(address(groupAdmin), address(phase), 4096, 32);

        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(banSource), address(0), address(0));

        _acceptDelegations();
        vm.prank(chatOwner);
        groupDelegate.setDelegateId(groupId, delegateId);

        vm.prank(delegateOwner);
        groupDelegate.setDelegationAcceptanceEnabled(delegateId, false);

        vm.roll(block.number + 50);
        assertTrue(_canPost(chat, groupId, delegateId));

        vm.prank(strangerOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.MentionAllUnauthorized.selector, groupId, strangerGroupId)
        );
        chat.post(groupId, strangerGroupId, "stranger", _emptyMentions(), true, 0);

        vm.prank(strangerOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGroupChatErrors.BanRejected.selector, groupId, strangerGroupId, address(banSource))
        );
        chat.post(groupId, strangerGroupId, "stranger", _emptyMentions(), false, 0);

        vm.prank(delegateOwner);
        chat.post(groupId, delegateId, "delegate", _emptyMentions(), true, 0);

        vm.prank(chatOwner);
        chat.post(groupId, groupId, "owner", _emptyMentions(), false, 0);

        assertEq(messagesTotal(chat, groupId), 2);
    }

    function testT154_missingGroupRejects() public {
        vm.expectRevert(abi.encodeWithSelector(IGroupChatDelegateErrors.GroupNotExist.selector, uint256(999)));
        groupDelegate.effectiveDelegateId(999);
    }

    function testT154B_setDelegateIdMissingGroupRejects() public {
        _acceptDelegations();

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatDelegateErrors.GroupNotExist.selector, uint256(999)));
        groupDelegate.setDelegateId(999, delegateId);
    }

    function _canPost(GroupChat chat, uint256 groupId_, uint256 senderId_) internal view returns (bool) {
        (bool allowed,) = chat.canPost(groupId_, senderId_);
        return allowed;
    }

    function _emptyMentions() internal pure returns (uint256[] memory mentionedSenderIds) {
        mentionedSenderIds = new uint256[](0);
    }

    function _uints(uint256 a) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = a;
    }

    function _uints(uint256 a, uint256 b) internal pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = a;
        values[1] = b;
    }
}
