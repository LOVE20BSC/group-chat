// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IGovVotedBanSource} from "../src/interfaces/sources/ban/IGovVotedBanSource.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

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

    function voteWeightOf(uint256, uint256) external view returns (uint256) {
        return _voteWeight;
    }
}

contract GovVotedBanSourceTest is GroupChatFixture {
    uint256 internal constant BAN_THRESHOLD_RATIO = 3e15;
    uint256 internal constant MIN_SUPPORT_TO_OPPOSE_MULTIPLIER = 10;

    MockLOVE20Protocols internal protocol;
    GovVotedBanSource internal banSource;
    TokenGovManager internal tokenGovManager;
    TokenActionGovManager internal actionGovManager;
    address internal token;
    address internal voter2Owner = address(0xB0B2);
    uint256 internal voter2Id;

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

    function testT129_constructorRejectsInvalidMinSupportToOpposeMultiplier() public {
        vm.expectRevert(IGovVotedBanSource.MinSupportToOpposeMultiplierZero.selector);
        new GovVotedBanSource(address(groupNft), 0, BAN_THRESHOLD_RATIO);
    }

    function testT130_tokenGovVoteAndOpposeAffectIsBannedAndGroupChat() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        protocol.setGovVotes(token, voter2Id, 5);
        protocol.setGovVotes(token, otherGroupId, 5);

        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 0);
        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));

        (bool allowed, bytes4 reasonCode) = _canPost(managerGroupId, otherGroupId);
        assertTrue(!allowed);
        assertEq(bytes32(reasonCode), bytes32(IGroupChatErrors.BanRejected.selector));

        vm.prank(voter2Owner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, voter2Id, false);

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
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);
        vm.prank(voter2Owner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, voter2Id, false);

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(!banned);
        assertEq(supportWeight, 100);
        assertEq(opposeWeight, 10);

        protocol.setGovVotes(token, senderId, 101);
        banSource.refreshVoteBySenderId(managerGroupId, otherGroupId, senderId);

        (banned, supportWeight, opposeWeight) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 101);
        assertEq(opposeWeight, 10);
        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT131_clearAndRefreshUpdateVoterWeightsAndRemoveVoteAtZero() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);

        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);
        assertEq(banSource.votersBySenderIdCount(managerGroupId, otherGroupId), 1);

        protocol.setGovVotes(token, senderId, 9);
        banSource.refreshVoteBySenderId(managerGroupId, otherGroupId, senderId);
        (, uint256 supportWeight,) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertEq(supportWeight, 9);

        protocol.setGovVotes(token, senderId, 0);
        banSource.refreshVoteBySenderId(managerGroupId, otherGroupId, senderId);
        assertEq(banSource.votersBySenderIdCount(managerGroupId, otherGroupId), 0);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));
        assertEq(banSource.votedSenderIdsCount(managerGroupId), 0);

        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);
        vm.prank(senderOwner);
        banSource.clearVoteBySenderId(managerGroupId, otherGroupId, senderId);
        assertEq(banSource.votersBySenderIdCount(managerGroupId, otherGroupId), 0);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT131C_stateVersionAdvancesOnlyOnSettledChanges() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        assertEq(banSource.stateVersion(managerGroupId), 0);

        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);
        uint256 afterVote = banSource.stateVersion(managerGroupId);
        assertEq(afterVote, 1);

        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.VoteUnchanged.selector);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);
        assertEq(banSource.stateVersion(managerGroupId), afterVote);

        protocol.setGovVotes(token, senderId, 8);
        banSource.refreshVoteBySenderId(managerGroupId, otherGroupId, senderId);
        uint256 afterRefresh = banSource.stateVersion(managerGroupId);
        assertEq(afterRefresh, afterVote + 1);

        banSource.refreshVoteBySenderId(managerGroupId, otherGroupId, senderId);
        assertEq(banSource.stateVersion(managerGroupId), afterRefresh);
    }

    function testT132_zeroWeightAndMissingVoteRevert() public {
        uint256 managerGroupId = _activateTokenGovManager();

        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.VoteWeightZero.selector);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.VoteNotFound.selector);
        banSource.clearVoteBySenderId(managerGroupId, otherGroupId, senderId);

        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        vm.prank(senderOwner);
        vm.expectRevert(IGovVotedBanSource.VoteUnchanged.selector);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999999)));
        banSource.voteBySenderId(managerGroupId, otherGroupId, 999999, true);
    }

    function testT133_readerDegradesWhenSourceUnavailable() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        groupNft.transferFrom(address(tokenGovManager), other, managerGroupId);

        assertTrue(banSource.isBanned(managerGroupId, otherGroupId));
        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(!banned);
        assertEq(supportWeight, 0);
        assertEq(opposeWeight, 0);
    }

    function testT134_actionGovManagerActsAsWeightSource() public {
        protocol.setActionsCount(token, 5);
        uint256 managerGroupId = actionGovManager.activate(token, 1);
        protocol.setActionVotes(token, 1, senderId, 1, 4);
        protocol.setGovVotes(token, senderId, 4);

        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        (bool banned, uint256 supportWeight,) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 4);
    }

    function testT134B_thresholdRequiresMinimumSupport() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 1);
        protocol.setGovVotes(token, voter2Id, 1000);

        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        (bool banned, uint256 supportWeight,) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(!banned);
        assertEq(supportWeight, 1);
    }

    function testT135_targetAndVoterPagination() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        protocol.setGovVotes(token, voter2Id, 5);

        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);
        vm.prank(voter2Owner);
        banSource.voteBySenderId(managerGroupId, groupId, voter2Id, true);

        assertEq(banSource.votedSenderIdsCount(managerGroupId), 2);
        (uint256[] memory targets,,, uint256[] memory voterCounts) =
            banSource.votedSenderIds(managerGroupId, 0, 10);
        assertEq(targets.length, 2);
        assertEq(voterCounts[0], 1);
        assertEq(voterCounts[1], 1);

        (uint256[] memory voters, uint256[] memory supportWeights,) =
            banSource.votersBySenderId(managerGroupId, otherGroupId, 0, 10);
        assertEq(voters.length, 1);
        assertEq(voters[0], senderId);
        assertEq(supportWeights[0], 7);
    }

    function testT136_voterSnapshotSurvivesNftTransfer() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        groupNft.transferFrom(senderOwner, other, senderId);

        (bool banned, uint256 supportWeight,) = banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 7);

        vm.prank(senderOwner);
        vm.expectRevert(abi.encodeWithSelector(IGovVotedBanSource.NotMemberOwner.selector, senderId));
        banSource.clearVoteBySenderId(managerGroupId, otherGroupId, senderId);

        vm.prank(other);
        banSource.clearVoteBySenderId(managerGroupId, otherGroupId, senderId);
        assertTrue(!banSource.isBanned(managerGroupId, otherGroupId));
    }

    function testT138_batchListChecksReturnIndependentCacheSlices() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        (bool[] memory banned, uint256[] memory supportWeights, uint256[] memory opposeWeights) =
            banSource.voteStatusBySenderIds(managerGroupId, _uints(otherGroupId, groupId));
        assertTrue(banned[0]);
        assertTrue(!banned[1]);
        assertEq(supportWeights[0], 7);
        assertEq(supportWeights[1], 0);
        assertEq(opposeWeights[0], 0);
        assertEq(opposeWeights[1], 0);

        assertEq(banSource.stateVersion(managerGroupId), 1);
    }

    function testT139_govVoteStatusReturnsSettledBannedAndTallies() public {
        uint256 managerGroupId = _activateTokenGovManager();
        protocol.setGovVotes(token, senderId, 7);
        vm.prank(senderOwner);
        banSource.voteBySenderId(managerGroupId, otherGroupId, senderId, true);

        (bool banned, uint256 supportWeight, uint256 opposeWeight) =
            banSource.voteStatusBySenderId(managerGroupId, otherGroupId);
        assertTrue(banned);
        assertEq(supportWeight, 7);
        assertEq(opposeWeight, 0);

        (uint256[] memory supportWeights, uint256[] memory opposeWeights) =
            banSource.voteWeightsBySenderIdsByVoter(managerGroupId, _uints(otherGroupId), senderId);
        assertEq(supportWeights[0], 7);
        assertEq(opposeWeights[0], 0);
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
