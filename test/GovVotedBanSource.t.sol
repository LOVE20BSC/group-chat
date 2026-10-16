// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IGovVotedBanSource} from "../src/interfaces/sources/ban/IGovVotedBanSource.sol";

import {TokenActionGovManager} from "../src/managers/TokenActionGovManager.sol";
import {TokenGovManager} from "../src/managers/TokenGovManager.sol";
import {GovVotedBanSource} from "../src/sources/ban/GovVotedBanSource.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";

contract MissingTotalBanVoteWeightSource {
    uint256 internal immutable _voteWeight;

    constructor(uint256 voteWeight_) {
        _voteWeight = voteWeight_;
    }

    function voteWeightOf(uint256, address) external view returns (uint256) {
        return _voteWeight;
    }
}

contract GovVotedBanSourceTest is GroupChatFixture {
    uint256 internal constant BAN_THRESHOLD_RATIO = 3e15;
    uint256 internal constant MIN_SUPPORT_TO_OPPOSE_RATIO = 10;

    MockLOVE20Protocols internal protocol;
    GovVotedBanSource internal banSource;
    TokenGovManager internal tokenGovManager;
    TokenActionGovManager internal actionGovManager;
    address internal token;
    address internal voter2 = address(0xB0B2);
    uint256 internal voter2GroupId;

    function setUp() public override {
        super.setUp();
        protocol = new MockLOVE20Protocols();
        token = address(protocol);
        banSource = new GovVotedBanSource(address(groupNft), MIN_SUPPORT_TO_OPPOSE_RATIO, BAN_THRESHOLD_RATIO);
        tokenGovManager =
            new TokenGovManager(address(chat), address(banSource), address(0), address(0), address(protocol));
        actionGovManager =
            new TokenActionGovManager(address(chat), address(banSource), address(0), address(0), address(protocol), 3);
        voter2GroupId = groupNft.mint(voter2);
    }

    function testT129_constructorRejectsInvalidMinSupportToOpposeRatio() public {
        vm.expectRevert(IGovVotedBanSource.MinSupportToOpposeRatioZero.selector);
        new GovVotedBanSource(address(groupNft), 0, BAN_THRESHOLD_RATIO);
    }

    function testT130_tokenGovVoteAndOpposeAffectIsBannedAndGroupChat() public {
        _activateTokenGovManager();
        protocol.setGovVotes(token, senderOwner, 7);
        protocol.setGovVotes(token, voter2, 5);

        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, senderOwner, true);

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderAddress(groupId, senderOwner);
        assertTrue(banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 0);
        assertTrue(banSource.isBanned(groupId, senderId, senderOwner));

        (bool allowed, bytes4 reasonCode) = _canPost(groupId, senderId, senderOwner);
        assertTrue(!allowed);
        assertEq(bytes32(reasonCode), bytes32(IGroupChatErrors.BanRejected.selector));

        vm.prank(voter2);
        banSource.voteBySenderAddress(groupId, senderOwner, false);

        (banned, supportWeight, opposeWeight) = banSource.voteStatusBySenderAddress(groupId, senderOwner);
        assertTrue(!banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 5);
        assertTrue(!banSource.isBanned(groupId, senderId, senderOwner));

        protocol.setGovVotes(token, voter2, 8);
        vm.prank(voter2);
        banSource.voteBySenderAddress(groupId, senderOwner, false);

        (banned, supportWeight, opposeWeight) = banSource.voteStatusBySenderAddress(groupId, senderOwner);
        assertTrue(!banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 8);
        assertTrue(!banSource.isBanned(groupId, senderId, senderOwner));
    }

    function testT130B_supportMustExceedTenTimesOppose() public {
        _activateTokenGovManager();
        protocol.setGovVotes(token, senderOwner, 100);
        protocol.setGovVotes(token, voter2, 10);

        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, senderOwner, true);
        vm.prank(voter2);
        banSource.voteBySenderAddress(groupId, senderOwner, false);

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderAddress(groupId, senderOwner);
        assertTrue(!banned);
        assertEq(supportWeight, 100);
        assertEq(opposeWeight, 10);
        assertTrue(!banSource.isBanned(groupId, senderId, senderOwner));

        protocol.setGovVotes(token, senderOwner, 101);
        banSource.refreshVoteBySenderAddress(groupId, senderOwner, senderOwner);

        (banned, supportWeight, opposeWeight) = banSource.voteStatusBySenderAddress(groupId, senderOwner);
        assertTrue(banned);
        assertEq(supportWeight, 101);
        assertEq(opposeWeight, 10);
        assertTrue(banSource.isBanned(groupId, senderId, senderOwner));
    }

    function testT131_clearAndRefreshUpdateVoterWeightsAndRemoveVoteAtZero() public {
        _activateTokenGovManager();
        protocol.setGovVotes(token, senderOwner, 9);

        vm.prank(senderOwner);
        banSource.voteBySenderId(groupId, senderId, true);
        assertTrue(banSource.isBanned(groupId, senderId, senderOwner));
        assertEq(banSource.votedSenderIdsCount(groupId), 1);
        assertEq(banSource.stateVersion(groupId), 1);

        protocol.setGovVotes(token, senderOwner, 4);
        banSource.refreshVoteBySenderId(groupId, senderId, senderOwner);
        uint256[] memory senderIds = new uint256[](1);
        senderIds[0] = senderId;
        (uint256[] memory supportWeights, uint256[] memory opposeWeights) =
            banSource.voteWeightsBySenderIdsByVoter(groupId, senderIds, senderOwner);
        assertEq(supportWeights.length, 1);
        assertEq(opposeWeights.length, 1);
        assertEq(supportWeights[0], 4);
        assertEq(opposeWeights[0], 0);
        assertEq(banSource.stateVersion(groupId), 2);

        protocol.setGovVotes(token, senderOwner, 0);
        banSource.refreshVoteBySenderId(groupId, senderId, senderOwner);
        (supportWeights, opposeWeights) = banSource.voteWeightsBySenderIdsByVoter(groupId, senderIds, senderOwner);
        assertEq(supportWeights[0], 0);
        assertEq(opposeWeights[0], 0);
        assertEq(banSource.votedSenderIdsCount(groupId), 0);
        assertEq(banSource.stateVersion(groupId), 3);

        protocol.setGovVotes(token, senderOwner, 6);
        vm.prank(senderOwner);
        banSource.voteBySenderId(groupId, senderId, true);
        vm.prank(senderOwner);
        banSource.clearVoteBySenderId(groupId, senderId);
        assertEq(banSource.votedSenderIdsCount(groupId), 0);
        assertEq(banSource.stateVersion(groupId), 5);
    }

    function testT132_zeroWeightUnchangedAndMissingVoteRevert() public {
        _activateTokenGovManager();

        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.VoteWeightZero.selector);
        banSource.voteBySenderAddress(groupId, senderOwner, true);

        protocol.setGovVotes(token, senderOwner, 3);
        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, senderOwner, true);

        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.VoteUnchanged.selector);
        banSource.voteBySenderAddress(groupId, senderOwner, true);

        vm.expectRevert(IGovVotedBanSource.VoteNotFound.selector);
        banSource.refreshVoteBySenderAddress(groupId, other, senderOwner);

        vm.prank(voter2);
        vm.expectRevert(IGovVotedBanSource.VoteNotFound.selector);
        banSource.clearVoteBySenderAddress(groupId, senderOwner);

        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.TargetSenderIdZero.selector);
        banSource.voteBySender(groupId, 0, senderOwner, true);

        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.TargetAddressZero.selector);
        banSource.voteBySender(groupId, senderId, address(0), true);
    }

    function testT133_readerDegradesWhenSourceUnavailable() public {
        assertEq(banSource.votedSenderAddressesCount(groupId), 0);
        assertEq(banSource.votedSenderIdsCount(groupId), 0);
        assertTrue(!banSource.isBanned(groupId, senderId, senderOwner));
        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderAddress(groupId, senderOwner);
        assertTrue(!banned);
        assertEq(supportWeight, 0);
        assertEq(opposeWeight, 0);
        address[] memory senderAddresses = new address[](1);
        senderAddresses[0] = senderOwner;
        (uint256[] memory voterSupportWeights, uint256[] memory voterOpposeWeights) =
            banSource.voteWeightsBySenderAddressesByVoter(groupId, senderAddresses, senderOwner);
        assertEq(voterSupportWeights.length, 1);
        assertEq(voterOpposeWeights.length, 1);
        assertEq(voterSupportWeights[0], 0);
        assertEq(voterOpposeWeights[0], 0);
        address[] memory voters;
        (voters, voterSupportWeights, voterOpposeWeights) = banSource.votersBySenderAddress(groupId, senderOwner, 0, 10);
        assertEq(voters.length, 0);
        assertEq(voterSupportWeights.length, 0);
        assertEq(voterOpposeWeights.length, 0);

        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.BanVoteWeightSourceUnavailable.selector);
        banSource.voteBySenderAddress(groupId, senderOwner, true);
    }

    function testT134_actionGovManagerActsAsWeightSource() public {
        protocol.setCurrentRound(7);
        protocol.setActionsCount(token, 43);
        groupId = actionGovManager.activate(token, 42);

        protocol.setActionVotes(token, 7, senderOwner, 42, 11);
        vm.prank(senderOwner);
        banSource.voteBySenderId(groupId, senderId, true);

        (bool banned, uint256 supportWeight, uint256 opposeWeight) = banSource.voteStatusBySenderId(groupId, senderId);
        assertTrue(!banned);
        assertEq(supportWeight, 11);
        assertEq(opposeWeight, 0);
    }

    function testT134B_thresholdRequiresMinimumSupport() public {
        _activateTokenGovManager();
        address whale = address(0xABCD);
        protocol.setGovVotes(token, senderOwner, 29);
        protocol.setGovVotes(token, voter2, 1);
        protocol.setGovVotes(token, whale, 9969);

        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, senderOwner, true);
        assertTrue(!banSource.isBanned(groupId, senderId, senderOwner));

        vm.prank(voter2);
        banSource.voteBySenderAddress(groupId, senderOwner, true);
        assertTrue(banSource.isBanned(groupId, senderId, senderOwner));
    }

    function testT134C_totalWeightFailureDoesNotSilentlyAllow() public {
        MissingTotalBanVoteWeightSource source = new MissingTotalBanVoteWeightSource(1);
        uint256 managedGroupId = groupNft.mint(address(source));
        assertTrue(!banSource.isBanned(managedGroupId, senderId, senderOwner));

        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.BanVoteWeightSourceUnavailable.selector);
        banSource.voteBySenderAddress(managedGroupId, senderOwner, true);
    }

    function testT134D_thresholdIsSettledOnWriteAndRefreshNotEveryRead() public {
        _activateTokenGovManager();
        address whale = address(0xABCD);
        protocol.setGovVotes(token, senderOwner, 30);

        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, senderOwner, true);
        assertTrue(banSource.isBanned(groupId, senderId, senderOwner));

        protocol.setGovVotes(token, whale, 10000);
        assertTrue(banSource.isBanned(groupId, senderId, senderOwner));

        banSource.refreshVoteBySenderAddress(groupId, senderOwner, senderOwner);
        assertTrue(!banSource.isBanned(groupId, senderId, senderOwner));
    }

    function testT135_targetAndVoterPagination() public {
        _activateTokenGovManager();
        protocol.setGovVotes(token, senderOwner, 2);
        protocol.setGovVotes(token, voter2, 4);

        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, senderOwner, true);
        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, other, true);
        vm.prank(voter2);
        banSource.voteBySenderAddress(groupId, senderOwner, false);

        (
            address[] memory senderAddresses,
            uint256[] memory supportWeights,
            uint256[] memory opposeWeights,
            uint256[] memory voterCounts
        ) = banSource.votedSenderAddresses(groupId, 0, 10);
        assertEq(senderAddresses.length, 2);
        assertEq(supportWeights.length, 2);
        assertEq(opposeWeights.length, 2);
        assertEq(voterCounts.length, 2);
        assertEq(senderAddresses[0], senderOwner);
        assertEq(supportWeights[0], 2);
        assertEq(opposeWeights[0], 4);
        assertEq(voterCounts[0], 2);

        (address[] memory voters, uint256[] memory voterSupportWeights, uint256[] memory voterOpposeWeights) =
            banSource.votersBySenderAddress(groupId, senderOwner, 0, 10);
        assertEq(voters.length, 2);
        assertEq(voterSupportWeights.length, 2);
        assertEq(voterOpposeWeights.length, 2);
        assertEq(voters[0], senderOwner);
        assertEq(voterSupportWeights[0], 2);
        assertEq(voterOpposeWeights[0], 0);
        assertEq(voters[1], voter2);
        assertEq(voterSupportWeights[1], 0);
        assertEq(voterOpposeWeights[1], 4);

        address[] memory queriedSenderAddresses = new address[](3);
        queriedSenderAddresses[0] = senderOwner;
        queriedSenderAddresses[1] = other;
        queriedSenderAddresses[2] = address(0x9999);
        (voterSupportWeights, voterOpposeWeights) =
            banSource.voteWeightsBySenderAddressesByVoter(groupId, queriedSenderAddresses, senderOwner);
        assertEq(voterSupportWeights.length, 3);
        assertEq(voterOpposeWeights.length, 3);
        assertEq(voterSupportWeights[0], 2);
        assertEq(voterOpposeWeights[0], 0);
        assertEq(voterSupportWeights[1], 2);
        assertEq(voterOpposeWeights[1], 0);
        assertEq(voterSupportWeights[2], 0);
        assertEq(voterOpposeWeights[2], 0);
    }

    function testT136_senderVoteUsesExplicitSnapshotAndSurvivesNftTransfer() public {
        _activateTokenGovManager();
        protocol.setGovVotes(token, senderOwner, 7);
        groupNft.transferFrom(senderOwner, other, senderId);

        vm.prank(senderOwner);
        banSource.voteBySender(groupId, senderId, senderOwner, true);

        (bool addressBanned, uint256 addressSupport, uint256 addressOppose) =
            banSource.voteStatusBySenderAddress(groupId, senderOwner);
        (bool senderIdBanned, uint256 groupSupport, uint256 groupOppose) =
            banSource.voteStatusBySenderId(groupId, senderId);
        assertTrue(addressBanned);
        assertTrue(senderIdBanned);
        assertEq(addressSupport, 7);
        assertEq(addressOppose, 0);
        assertEq(groupSupport, 7);
        assertEq(groupOppose, 0);
        assertEq(groupNft.ownerOf(senderId), other);
        assertTrue(banSource.isBanned(groupId, senderId, senderOwner));
        assertEq(banSource.stateVersion(groupId), 1);

        protocol.setGovVotes(token, senderOwner, 4);
        banSource.refreshVoteBySender(groupId, senderId, senderOwner, senderOwner);

        (addressBanned, addressSupport, addressOppose) = banSource.voteStatusBySenderAddress(groupId, senderOwner);
        (senderIdBanned, groupSupport, groupOppose) = banSource.voteStatusBySenderId(groupId, senderId);
        assertTrue(addressBanned);
        assertTrue(senderIdBanned);
        assertEq(addressSupport, 4);
        assertEq(addressOppose, 0);
        assertEq(groupSupport, 4);
        assertEq(groupOppose, 0);
        assertEq(banSource.stateVersion(groupId), 2);

        vm.prank(senderOwner);
        banSource.voteBySender(groupId, senderId, senderOwner, false);

        (addressBanned, addressSupport, addressOppose) = banSource.voteStatusBySenderAddress(groupId, senderOwner);
        (senderIdBanned, groupSupport, groupOppose) = banSource.voteStatusBySenderId(groupId, senderId);
        assertTrue(!addressBanned);
        assertTrue(!senderIdBanned);
        assertEq(addressSupport, 0);
        assertEq(addressOppose, 4);
        assertEq(groupSupport, 0);
        assertEq(groupOppose, 4);
        assertTrue(!banSource.isBanned(groupId, senderId, senderOwner));
        assertEq(banSource.stateVersion(groupId), 3);

        vm.prank(senderOwner);
        banSource.clearVoteBySender(groupId, senderId, senderOwner);

        assertEq(banSource.votedSenderAddressesCount(groupId), 0);
        assertEq(banSource.votedSenderIdsCount(groupId), 0);
        assertEq(banSource.stateVersion(groupId), 4);
    }

    function testT137_senderAddressVoteOnlyTouchesAddressTarget() public {
        _activateTokenGovManager();
        protocol.setGovVotes(token, senderOwner, 7);
        protocol.setGovVotes(token, voter2, 5);
        groupNft.transferFrom(senderOwner, other, senderId);

        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, senderOwner, true);

        (bool addressBanned, uint256 addressSupport, uint256 addressOppose) =
            banSource.voteStatusBySenderAddress(groupId, senderOwner);
        (bool senderIdBanned, uint256 groupSupport, uint256 groupOppose) =
            banSource.voteStatusBySenderId(groupId, senderId);
        assertTrue(addressBanned);
        assertTrue(!senderIdBanned);
        assertEq(addressSupport, 7);
        assertEq(addressOppose, 0);
        assertEq(groupSupport, 0);
        assertEq(groupOppose, 0);
        assertEq(banSource.votedSenderIdsCount(groupId), 0);

        vm.prank(voter2);
        banSource.voteBySenderAddress(groupId, voter2, true);

        (addressBanned, addressSupport, addressOppose) = banSource.voteStatusBySenderAddress(groupId, voter2);
        assertTrue(addressBanned);
        assertEq(addressSupport, 5);
        assertEq(addressOppose, 0);
        assertEq(banSource.votedSenderIdsCount(groupId), 0);
        assertEq(banSource.stateVersion(groupId), 2);
    }

    function testT138_batchListChecksReturnIndependentCacheSlices() public {
        _activateTokenGovManager();
        protocol.setGovVotes(token, senderOwner, 7);

        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, senderOwner, true);

        uint256[] memory senderIds = new uint256[](2);
        senderIds[0] = senderId;
        senderIds[1] = otherGroupId;
        address[] memory senderAddresses = new address[](2);
        senderAddresses[0] = senderOwner;
        senderAddresses[1] = other;

        bool[] memory addressBanned = banSource.isAddressBannedBatch(groupId, senderAddresses);
        assertEq(addressBanned.length, 2);
        assertTrue(addressBanned[0]);
        assertTrue(!addressBanned[1]);

        bool[] memory senderIdBanned = banSource.isSenderIdBannedBatch(groupId, senderIds);
        assertEq(senderIdBanned.length, 2);
        assertTrue(!senderIdBanned[0]);
        assertTrue(!senderIdBanned[1]);

        protocol.setGovVotes(token, voter2, 8);
        vm.prank(voter2);
        banSource.voteBySenderAddress(groupId, senderOwner, false);

        addressBanned = banSource.isAddressBannedBatch(groupId, senderAddresses);
        assertEq(addressBanned.length, 2);
        assertTrue(!addressBanned[0]);
        assertTrue(!addressBanned[1]);
    }

    function testT139_govVoteStatusReturnsSettledBannedAndTallies() public {
        _activateTokenGovManager();
        address whale = address(0xABCD);
        protocol.setGovVotes(token, senderOwner, 20);
        protocol.setGovVotes(token, voter2, 5);
        protocol.setGovVotes(token, whale, 10000);

        vm.prank(senderOwner);
        banSource.voteBySenderAddress(groupId, senderOwner, true);
        vm.prank(voter2);
        banSource.voteBySenderAddress(groupId, senderOwner, false);
        vm.prank(whale);
        banSource.voteBySenderAddress(groupId, other, true);

        vm.prank(senderOwner);
        banSource.voteBySenderId(groupId, senderId, true);
        vm.prank(whale);
        banSource.voteBySenderId(groupId, otherGroupId, true);

        address[] memory senderAddresses = new address[](3);
        senderAddresses[0] = senderOwner;
        senderAddresses[1] = other;
        senderAddresses[2] = address(0x9999);

        (bool[] memory banned, uint256[] memory supportWeights, uint256[] memory opposeWeights) =
            banSource.voteStatusBySenderAddresses(groupId, senderAddresses);
        assertEq(banned.length, 3);
        assertTrue(!banned[0]);
        assertTrue(banned[1]);
        assertTrue(!banned[2]);
        assertEq(supportWeights[0], 20);
        assertEq(supportWeights[1], 10000);
        assertEq(supportWeights[2], 0);
        assertEq(opposeWeights[0], 5);
        assertEq(opposeWeights[1], 0);
        assertEq(opposeWeights[2], 0);

        uint256[] memory senderIds = new uint256[](3);
        senderIds[0] = senderId;
        senderIds[1] = otherGroupId;
        senderIds[2] = 999999;

        (banned, supportWeights, opposeWeights) = banSource.voteStatusBySenderIds(groupId, senderIds);
        assertEq(banned.length, 3);
        assertTrue(!banned[0]);
        assertTrue(banned[1]);
        assertTrue(!banned[2]);
        assertEq(supportWeights[0], 20);
        assertEq(supportWeights[1], 10000);
        assertEq(supportWeights[2], 0);
        assertEq(opposeWeights[0], 0);
        assertEq(opposeWeights[1], 0);
        assertEq(opposeWeights[2], 0);
    }

    function _activateTokenGovManager() internal {
        groupId = tokenGovManager.activate(token);
    }
}
