// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IGovVotedBanSourceErrors} from "../src/interfaces/sources/ban/IGovVotedBanSource.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {TokenActionGovManager} from "../src/managers/TokenActionGovManager.sol";
import {TokenGovManager} from "../src/managers/TokenGovManager.sol";
import {GovVotedBanSource} from "../src/sources/ban/GovVotedBanSource.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract MissingTotalBanVoteWeightSource {
    uint256 internal immutable _voteWeight;

    constructor(uint256 voteWeight_) {
        _voteWeight = voteWeight_;
    }

    function voteWeight(uint256, uint256) external view returns (uint256) {
        return _voteWeight;
    }
}

contract GovVotedBanSourceTest is GroupChatFixture {
    uint256 internal constant BAN_THRESHOLD_RATIO = 3e15;
    uint256 internal constant MIN_SUPPORT_TO_OPPOSE_MULTIPLIER = 10;
    uint256 internal constant THIRD_TARGET_SENDER_ID = 0xAA01;

    MockLOVE20Protocols internal protocol;
    GovVotedBanSource internal banSource;
    TokenGovManager internal tokenGovManager;
    TokenActionGovManager internal actionGovManager;
    address internal token;
    address internal voter2Owner = address(0xB0B2);
    uint256 internal voter2Id;

    bytes32 internal constant SENDER_BAN_VOTE_CAST_SIG =
        keccak256("SenderBanVoteCast(uint256,uint256,uint256,bool,uint256,uint256,uint256)");
    bytes32 internal constant SENDER_BAN_VOTE_CLEARED_SIG =
        keccak256("SenderBanVoteCleared(uint256,uint256,uint256,bool,uint256,uint256,uint256)");
    bytes32 internal constant GOV_SENDER_BAN_CHANGED_SIG =
        keccak256("GovSenderBanChanged(uint256,uint256,bool,uint256,uint256,uint256)");

    function setUp() public override {
        super.setUp();
        protocol = new MockLOVE20Protocols();
        token = address(protocol);
        banSource = new GovVotedBanSource(address(groupNft), MIN_SUPPORT_TO_OPPOSE_MULTIPLIER, BAN_THRESHOLD_RATIO);
        tokenGovManager =
            new TokenGovManager(address(chat), address(banSource), address(0), address(0), address(protocol));
        actionGovManager =
            new TokenActionGovManager(address(chat), address(banSource), address(0), address(0), address(protocol), 3);
        voter2Id = groupNft.mint(voter2Owner);
    }

    function testT130_tokenGovVoteAndOpposeAffectIsBannedAndGroupChat() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        protocol.setGovVotes(token, voter2Id, 5);
        protocol.setGovVotes(token, otherGroupId, 5);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 0);
        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));

        (bool allowed, IGroupChat.PostRejectionReason reason) = _canPost(managerGroupId, otherGroupId);
        assertTrue(!allowed);
        assertEq(reason, IGroupChat.PostRejectionReason.BanRejected);

        vm.prank(voter2Owner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, voter2Id, false);

        (banned, supportWeight, opposeWeight) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(!banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 5);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT130B_supportMustExceedTenTimesOppose() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 100);
        protocol.setGovVotes(token, voter2Id, 10);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        vm.prank(voter2Owner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, voter2Id, false);

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(!banned);
        assertEq(supportWeight, 100);
        assertEq(opposeWeight, 10);

        protocol.setGovVotes(token, senderId, 101);
        banSource.refreshVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);

        (banned, supportWeight, opposeWeight) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 101);
        assertEq(opposeWeight, 10);
        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT130C_voteEventsCarryWeightsAndListedState() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);

        vm.recordLogs();
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(banSource));
        assertEq(logs[0].topics[0], SENDER_BAN_VOTE_CAST_SIG);
        assertEq(logs[0].topics[1], bytes32(managerGroupId));
        assertEq(logs[0].topics[2], bytes32(otherGroupId));
        assertEq(logs[0].topics[3], bytes32(senderId));
        (bool supportBan, uint256 settledWeight, uint256 supportWeight, uint256 opposeWeight) =
            abi.decode(logs[0].data, (bool, uint256, uint256, uint256));
        assertTrue(supportBan);
        assertEq(settledWeight, 7);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 0);

        _assertGovSenderBanChanged(logs[1], managerGroupId, otherGroupId, true, 7, 7, 0);
    }

    function testT131_clearAndRefreshUpdateVoterWeightsAndRemoveVoteAtZero() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        assertEq(votersBySenderIdTotal(banSource, managerGroupId, otherGroupId), 1);

        protocol.setGovVotes(token, senderId, 9);
        banSource.refreshVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);
        (, uint256 supportWeight,) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertEq(supportWeight, 9);

        protocol.setGovVotes(token, senderId, 0);
        vm.recordLogs();
        banSource.refreshVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], SENDER_BAN_VOTE_CLEARED_SIG);
        assertEq(logs[1].topics[0], GOV_SENDER_BAN_CHANGED_SIG);
        _assertGovSenderBanChanged(logs[1], managerGroupId, otherGroupId, false, 0, 0, 0);
        assertEq(votersBySenderIdTotal(banSource, managerGroupId, otherGroupId), 0);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));
        assertEq(votedSenderIdsTotal(banSource, managerGroupId), 0);

        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        vm.prank(senderOwner);
        banSource.clearVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);
        assertEq(votersBySenderIdTotal(banSource, managerGroupId, otherGroupId), 0);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT131C_identicalRecastRevertsEvenWhenListWouldFlip() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));

        vm.recordLogs();
        banSource.refreshVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);
        assertEq(vm.getRecordedLogs().length, 0);

        // Live total weight moved so a sync would unlist; the identical re-cast must still revert.
        protocol.setGovVotes(token, voter2Id, 3000);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovVotedBanSourceErrors.VoteUnchanged.selector, managerGroupId, otherGroupId, senderId
            )
        );
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));

        vm.recordLogs();
        banSource.refreshVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        _assertGovSenderBanChanged(logs[0], managerGroupId, otherGroupId, false, 3007, 7, 0);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT131D_belowThresholdEmitsVoteEventOnly() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 1);
        protocol.setGovVotes(token, voter2Id, 1000);

        vm.recordLogs();
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Below the 0.3% threshold: the ban list does not flip, so only the vote event is emitted.
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(banSource));
        assertEq(logs[0].topics[0], SENDER_BAN_VOTE_CAST_SIG);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT131E_clearEmitsClearedWithPreviousStanceAndWeights() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        protocol.setGovVotes(token, voter2Id, 5);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));

        // A second voter flips the list while both votes stay live: post totals span two voters.
        vm.recordLogs();
        vm.prank(voter2Owner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, voter2Id, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(banSource));
        assertEq(logs[0].topics[0], SENDER_BAN_VOTE_CAST_SIG);
        assertEq(logs[0].topics[3], bytes32(voter2Id));
        (bool castSupportBan, uint256 castSettledWeight, uint256 castSupportWeight, uint256 castOpposeWeight) =
            abi.decode(logs[0].data, (bool, uint256, uint256, uint256));
        assertTrue(!castSupportBan);
        assertEq(castSettledWeight, 5);
        assertEq(castSupportWeight, 7);
        assertEq(castOpposeWeight, 5);

        _assertGovSenderBanChanged(logs[1], managerGroupId, otherGroupId, false, 12, 7, 5);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));

        vm.recordLogs();
        vm.prank(senderOwner);
        banSource.clearVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);
        logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(banSource));
        assertEq(logs[0].topics[0], SENDER_BAN_VOTE_CLEARED_SIG);
        assertEq(logs[0].topics[1], bytes32(managerGroupId));
        assertEq(logs[0].topics[2], bytes32(otherGroupId));
        assertEq(logs[0].topics[3], bytes32(senderId));
        (bool prevSupportBan, uint256 prevSettledWeight, uint256 supportWeight, uint256 opposeWeight) =
            abi.decode(logs[0].data, (bool, uint256, uint256, uint256));
        assertTrue(prevSupportBan);
        assertEq(prevSettledWeight, 7);
        assertEq(supportWeight, 0);
        assertEq(opposeWeight, 5);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        protocol.setGovVotes(token, voter2Id, 0);

        vm.recordLogs();
        banSource.refreshVoteByTargetSenderId(managerGroupId, otherGroupId, voter2Id);
        logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(banSource));
        assertEq(logs[0].topics[0], SENDER_BAN_VOTE_CLEARED_SIG);
        assertEq(logs[0].topics[1], bytes32(managerGroupId));
        assertEq(logs[0].topics[2], bytes32(otherGroupId));
        assertEq(logs[0].topics[3], bytes32(voter2Id));
        (prevSupportBan, prevSettledWeight, supportWeight, opposeWeight) =
            abi.decode(logs[0].data, (bool, uint256, uint256, uint256));
        assertTrue(!prevSupportBan);
        assertEq(prevSettledWeight, 5);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 0);

        _assertGovSenderBanChanged(logs[1], managerGroupId, otherGroupId, true, 7, 7, 0);
        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT131F_sameVoterFlipBetweenSupportAndOppose() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));

        vm.recordLogs();
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(!banned);
        assertEq(supportWeight, 0);
        assertEq(opposeWeight, 7);
        assertEq(votersBySenderIdTotal(banSource, managerGroupId, otherGroupId), 1);

        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(banSource));
        assertEq(logs[0].topics[0], SENDER_BAN_VOTE_CAST_SIG);
        assertEq(logs[0].topics[1], bytes32(managerGroupId));
        assertEq(logs[0].topics[2], bytes32(otherGroupId));
        assertEq(logs[0].topics[3], bytes32(senderId));
        (bool castSupportBan, uint256 castSettledWeight, uint256 castSupportWeight, uint256 castOpposeWeight) =
            abi.decode(logs[0].data, (bool, uint256, uint256, uint256));
        assertTrue(!castSupportBan);
        assertEq(castSettledWeight, 7);
        assertEq(castSupportWeight, 0);
        assertEq(castOpposeWeight, 7);
        _assertGovSenderBanChanged(logs[1], managerGroupId, otherGroupId, false, 7, 0, 7);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        (banned, supportWeight, opposeWeight) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 0);
        assertEq(votersBySenderIdTotal(banSource, managerGroupId, otherGroupId), 1);
    }

    function testT131G_flipRemovesStoredWeightNotCurrentWeight() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        protocol.setGovVotes(token, senderId, 9);

        vm.recordLogs();
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(!banned);
        assertEq(supportWeight, 0);
        assertEq(opposeWeight, 9);
        assertEq(votersBySenderIdTotal(banSource, managerGroupId, otherGroupId), 1);

        assertEq(logs.length, 2);
        (bool castSupportBan, uint256 castSettledWeight, uint256 castSupportWeight, uint256 castOpposeWeight) =
            abi.decode(logs[0].data, (bool, uint256, uint256, uint256));
        assertTrue(!castSupportBan);
        assertEq(castSettledWeight, 9);
        assertEq(castSupportWeight, 0);
        assertEq(castOpposeWeight, 9);
        _assertGovSenderBanChanged(logs[1], managerGroupId, otherGroupId, false, 9, 0, 9);
    }

    function testT132_zeroWeightAndMissingVoteRevert() public {
        uint256 managerGroupId = _activateTokenGovManager();

        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGovVotedBanSourceErrors.ZeroVoteWeight.selector, managerGroupId, senderId)
        );
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovVotedBanSourceErrors.VoteNotFound.selector, managerGroupId, otherGroupId, senderId
            )
        );
        banSource.clearVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovVotedBanSourceErrors.VoteUnchanged.selector, managerGroupId, otherGroupId, senderId
            )
        );
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999999)));
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, 999999, true);
    }

    function testT132B_voteOnMissingGroupReportsGroupNotExist() public {
        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IGovVotedBanSourceErrors.GroupNotExist.selector, uint256(999_999))
        );
        banSource.voteByTargetSenderId(999_999, otherGroupId, senderId, true);
    }

    function testT132C_zeroTargetSenderIdRejected() public {
        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGovVotedBanSourceErrors.ZeroTargetSenderId.selector));
        banSource.voteByTargetSenderId(groupId, 0, senderId, true);
    }

    function testT133_readersReturnSettledStateWhenSourceUnavailable() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        groupNft.transferFrom(address(tokenGovManager), other, managerGroupId);

        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));
        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 0);

        uint256[] memory senderIds = new uint256[](1);
        senderIds[0] = otherGroupId;
        (bool[] memory bannedBatch, uint256[] memory supportWeightsBatch, uint256[] memory opposeWeightsBatch) =
            banSource.voteStatusBySenderIds(managerGroupId, senderIds);
        assertTrue(bannedBatch[0]);
        assertEq(supportWeightsBatch[0], 7);
        assertEq(opposeWeightsBatch[0], 0);
    }

    function testT133B_voteWithUnavailableSourceReverts() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        groupNft.transferFrom(address(tokenGovManager), other, managerGroupId);

        vm.prank(senderOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovVotedBanSourceErrors.BanVoteWeightSourceUnavailable.selector, managerGroupId, other
            )
        );
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
    }

    function testT134_actionGovManagerActsAsWeightSource() public {
        protocol.setActionsCount(token, 5);
        uint256 managerGroupId = actionGovManager.activate(token, 1);
        protocol.setActionVotes(token, 1, senderId, 1, 4);
        protocol.setGovVotes(token, senderId, 4);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        (bool banned, uint256 supportWeight,) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 4);
    }

    function testT134B_thresholdRequiresMinimumSupport() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 1);
        protocol.setGovVotes(token, voter2Id, 1000);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        (bool banned, uint256 supportWeight,) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(!banned);
        assertEq(supportWeight, 1);
    }

    function testT135_targetAndVoterPagination() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        protocol.setGovVotes(token, voter2Id, 5);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        vm.prank(voter2Owner);
        banSource.voteByTargetSenderId(managerGroupId, groupId, voter2Id, true);

        assertEq(votedSenderIdsTotal(banSource, managerGroupId), 2);
        (uint256[] memory targets,,, uint256[] memory voterCounts, uint256 targetTotal) =
            banSource.votedSenderIds(managerGroupId, 0, 10, false);
        assertEq(targetTotal, 2);
        assertEq(targets.length, 2);
        assertEq(voterCounts[0], 1);
        assertEq(voterCounts[1], 1);

        (uint256[] memory voters, uint256[] memory supportWeights,, uint256 voterTotal) =
            banSource.votersBySenderId(managerGroupId, otherGroupId, 0, 10, false);
        assertEq(voterTotal, 1);
        assertEq(voters.length, 1);
        assertEq(voters[0], senderId);
        assertEq(supportWeights[0], 7);
    }

    function testT135B_votedSenderIdsReverseWalksCurrentStorageOrder() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        protocol.setGovVotes(token, voter2Id, 5);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, groupId, senderId, true);
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, THIRD_TARGET_SENDER_ID, senderId, true);
        // The second voter only backs `groupId`, so `voterCounts` can tell the two orders apart.
        vm.prank(voter2Owner);
        banSource.voteByTargetSenderId(managerGroupId, groupId, voter2Id, true);
        assertEq(votedSenderIdsTotal(banSource, managerGroupId), 3);

        // Clearing the first target's only vote fills its slot with the last element, so storage
        // order becomes [THIRD_TARGET_SENDER_ID, groupId].
        vm.prank(senderOwner);
        banSource.clearVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);

        (uint256[] memory forward,,, uint256[] memory forwardVoterCounts, uint256 forwardTotal) =
            banSource.votedSenderIds(managerGroupId, 0, 10, false);
        assertEq(forwardTotal, 2);
        assertEq(forward[0], THIRD_TARGET_SENDER_ID);
        assertEq(forward[1], groupId);
        assertEq(forwardVoterCounts[0], 1);
        assertEq(forwardVoterCounts[1], 2);

        (uint256[] memory reversed,,, uint256[] memory reversedVoterCounts, uint256 reversedTotal) =
            banSource.votedSenderIds(managerGroupId, 0, 10, true);
        assertEq(reversedTotal, 2);
        assertEq(reversed[0], groupId);
        assertEq(reversed[1], THIRD_TARGET_SENDER_ID);
        assertEq(reversedVoterCounts[0], 2);
        assertEq(reversedVoterCounts[1], 1);
    }

    function testT135C_votersBySenderIdReverseWalksCurrentStorageOrder() public {
        uint256 managerGroupId = _activateTokenGovManager();
        address voter3Owner = address(0xB0B3);
        uint256 voter3Id = groupNft.mint(voter3Owner);
        protocol.setGovVotes(token, senderId, 7);
        protocol.setGovVotes(token, voter2Id, 5);
        protocol.setGovVotes(token, voter3Id, 3);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);
        vm.prank(voter2Owner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, voter2Id, true);
        vm.prank(voter3Owner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, voter3Id, true);
        assertEq(votersBySenderIdTotal(banSource, managerGroupId, otherGroupId), 3);

        // Clearing the first voter fills its slot with the last one, so storage order becomes
        // [voter3Id, voter2Id]; the weights pin the alignment of each page row.
        vm.prank(senderOwner);
        banSource.clearVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);

        (uint256[] memory forward, uint256[] memory forwardWeights,, uint256 forwardTotal) =
            banSource.votersBySenderId(managerGroupId, otherGroupId, 0, 10, false);
        assertEq(forwardTotal, 2);
        assertEq(forward[0], voter3Id);
        assertEq(forward[1], voter2Id);
        assertEq(forwardWeights[0], 3);
        assertEq(forwardWeights[1], 5);

        (uint256[] memory reversed, uint256[] memory reversedWeights,, uint256 reversedTotal) =
            banSource.votersBySenderId(managerGroupId, otherGroupId, 0, 10, true);
        assertEq(reversedTotal, 2);
        assertEq(reversed[0], voter2Id);
        assertEq(reversed[1], voter3Id);
        assertEq(reversedWeights[0], 5);
        assertEq(reversedWeights[1], 3);
    }

    function testT136_voterSnapshotSurvivesNftTransfer() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        groupNft.transferFrom(senderOwner, other, senderId);

        (bool banned, uint256 supportWeight,) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 7);

        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGovVotedBanSourceErrors.NotMemberOwner.selector, senderId));
        banSource.clearVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);

        vm.prank(other);
        banSource.clearVoteByTargetSenderId(managerGroupId, otherGroupId, senderId);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT138_batchListChecksReturnIndependentCacheSlices() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        (bool[] memory banned, uint256[] memory supportWeights, uint256[] memory opposeWeights) =
            banSource.voteStatusBySenderIds(managerGroupId, _uints(otherGroupId, groupId));
        assertTrue(banned[0]);
        assertTrue(!banned[1]);
        assertEq(supportWeights[0], 7);
        assertEq(supportWeights[1], 0);
        assertEq(opposeWeights[0], 0);
        assertEq(opposeWeights[1], 0);
    }

    function testT139_govVoteStatusReturnsSettledBannedAndTallies() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 0);

        (uint256[] memory supportWeights, uint256[] memory opposeWeights) =
            banSource.voteWeightsBySenderIdsByVoterId(managerGroupId, _uints(otherGroupId), senderId);
        assertEq(supportWeights[0], 7);
        assertEq(opposeWeights[0], 0);
    }

    function testT140_batchBannedMatchesSingleTargetReads() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);

        vm.prank(senderOwner);
        banSource.voteByTargetSenderId(managerGroupId, otherGroupId, senderId, true);

        uint256[] memory targets = new uint256[](3);
        targets[0] = otherGroupId;
        targets[1] = groupId;
        targets[2] = THIRD_TARGET_SENDER_ID;

        bool[] memory banned = banSource.isSenderIdBannedBatch(managerGroupId, targets);
        assertEq(banned.length, targets.length);
        assertTrue(banned[0]);
        assertTrue(!banned[1]);
        assertTrue(!banned[2]);
        for (uint256 i = 0; i < targets.length; i++) {
            assertEq(banned[i], banSource.isBanned(managerGroupId, targets[i]));
        }
    }

    function _assertGovSenderBanChanged(
        Vm.Log memory log,
        uint256 groupId_,
        uint256 targetSenderId,
        bool listed,
        uint256 totalVoteWeight,
        uint256 supportWeight,
        uint256 opposeWeight
    ) internal view {
        assertEq(log.emitter, address(banSource));
        assertEq(log.topics[0], GOV_SENDER_BAN_CHANGED_SIG);
        assertEq(log.topics[1], bytes32(groupId_));
        assertEq(log.topics[2], bytes32(targetSenderId));
        (bool actualListed, uint256 actualTotalVoteWeight, uint256 actualSupportWeight, uint256 actualOpposeWeight) =
            abi.decode(log.data, (bool, uint256, uint256, uint256));
        assertEq(actualListed, listed);
        assertEq(actualTotalVoteWeight, totalVoteWeight);
        assertEq(actualSupportWeight, supportWeight);
        assertEq(actualOpposeWeight, opposeWeight);
        assertEq(
            listed,
            totalVoteWeight != 0 && _ratioSatisfied(supportWeight, opposeWeight)
                && supportWeight * 1e18 >= totalVoteWeight * BAN_THRESHOLD_RATIO
        );
    }

    function _ratioSatisfied(uint256 supportWeight, uint256 opposeWeight) internal pure returns (bool) {
        if (opposeWeight == 0) {
            return supportWeight > 0;
        }
        uint256 quotient = supportWeight / opposeWeight;
        return quotient > MIN_SUPPORT_TO_OPPOSE_MULTIPLIER
            || (quotient == MIN_SUPPORT_TO_OPPOSE_MULTIPLIER && supportWeight % opposeWeight != 0);
    }

    function _activateTokenGovManager() internal returns (uint256 managerGroupId) {
        managerGroupId = tokenGovManager.activate(token);
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
