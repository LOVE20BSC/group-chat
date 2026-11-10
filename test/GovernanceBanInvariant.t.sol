// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {StdInvariant} from "@forge-std/StdInvariant.sol";

import {GovVotedBanSource} from "../src/sources/ban/GovVotedBanSource.sol";
import {TokenGovManager} from "../src/managers/TokenGovManager.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

// 随机动作面：cast / flip / refresh / clear 覆盖治理封禁的全部写路径。动作用 try/catch 包住，
// 随机输入被拒（零权重、无记录、重复投票）时不中断整轮调用。
contract BanVoteHandler {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    GovVotedBanSource internal immutable source;
    MockLOVE20Protocols internal immutable protocol;
    address internal immutable token;
    uint256 internal immutable groupId;
    uint256[3] internal targets;
    uint256[3] internal voters;
    address[3] internal owners;

    constructor(
        GovVotedBanSource source_,
        MockLOVE20Protocols protocol_,
        uint256 groupId_,
        uint256[3] memory targets_,
        uint256[3] memory voters_,
        address[3] memory owners_
    ) {
        source = source_;
        protocol = protocol_;
        token = address(protocol_);
        groupId = groupId_;
        targets = targets_;
        voters = voters_;
        owners = owners_;
    }

    function cast(uint256 targetSeed, uint256 voterSeed, uint256 weight, bool support) external {
        uint256 voter = voters[voterSeed % 3];
        protocol.setGovVotes(token, voter, weight % 20);
        vm.prank(owners[voterSeed % 3]);
        try source.voteByTargetSenderId(groupId, targets[targetSeed % 3], voter, support) {} catch {}
    }

    // 显式翻转立场：随机 cast 不一定在同一 (target, voter) 上连续两次，改票路径会落空。
    function flip(uint256 targetSeed, uint256 voterSeed, uint256 weight) external {
        uint256 target = targets[targetSeed % 3];
        uint256 voter = voters[voterSeed % 3];
        uint256[] memory one = new uint256[](1);
        one[0] = target;
        (uint256[] memory supportWeights,) = source.voteWeightsBySenderIdsByVoterId(groupId, one, voter);
        protocol.setGovVotes(token, voter, weight % 20);
        vm.prank(owners[voterSeed % 3]);
        try source.voteByTargetSenderId(groupId, target, voter, supportWeights[0] == 0) {} catch {}
    }

    function refresh(uint256 targetSeed, uint256 voterSeed, uint256 weight) external {
        uint256 voter = voters[voterSeed % 3];
        protocol.setGovVotes(token, voter, weight % 20);
        try source.refreshVoteByTargetSenderId(groupId, targets[targetSeed % 3], voter) {} catch {}
    }

    function clear(uint256 targetSeed, uint256 voterSeed) external {
        vm.prank(owners[voterSeed % 3]);
        try source.clearVoteByTargetSenderId(groupId, targets[targetSeed % 3], voters[voterSeed % 3]) {} catch {}
    }
}

contract GovernanceBanInvariantTest is GroupChatFixture, StdInvariant {
    uint256 internal constant MIN_SUPPORT_TO_OPPOSE_MULTIPLIER = 10;
    uint256 internal constant BAN_THRESHOLD_RATIO = 3e15;
    uint256 internal constant TARGET_COUNT = 3;

    MockLOVE20Protocols internal protocol;
    GovVotedBanSource internal banSource;
    uint256 internal managerGroupId;
    uint256[3] internal targets;
    uint256[3] internal voters;
    address[3] internal voterOwners;

    function setUp() public override {
        super.setUp();
        protocol = new MockLOVE20Protocols();
        banSource = new GovVotedBanSource(address(groupNft), MIN_SUPPORT_TO_OPPOSE_MULTIPLIER, BAN_THRESHOLD_RATIO);
        TokenGovManager manager =
            new TokenGovManager(address(chat), address(banSource), address(0), address(0), address(protocol));
        managerGroupId = manager.activate(address(protocol));

        targets[0] = 0xAA01;
        targets[1] = 0xAA02;
        targets[2] = 0xAA03;
        voters[0] = senderId;
        voters[1] = otherGroupId;
        voters[2] = thirdMemberId;
        voterOwners[0] = senderOwner;
        voterOwners[1] = other;
        voterOwners[2] = thirdMemberOwner;

        targetContract(
            address(new BanVoteHandler(banSource, protocol, managerGroupId, targets, voters, voterOwners))
        );
    }

    // 每个目标的 support/oppose 总量必须恒等于逐票 settledWeight 之和：增量结算的全部正确性压在这里。
    function invariant_totalsEqualTheSumOfSettledVotes() public view {
        uint256[] memory targetList = new uint256[](TARGET_COUNT);
        for (uint256 i = 0; i < TARGET_COUNT; i++) {
            targetList[i] = targets[i];
        }
        for (uint256 t = 0; t < TARGET_COUNT; t++) {
            (, uint256 supportWeight, uint256 opposeWeight) = banSource.voteStatusBySenderId(managerGroupId, targets[t]);
            uint256 expectedSupport;
            uint256 expectedOppose;
            for (uint256 v = 0; v < TARGET_COUNT; v++) {
                (uint256[] memory supportWeights, uint256[] memory opposeWeights) =
                    banSource.voteWeightsBySenderIdsByVoterId(managerGroupId, targetList, voters[v]);
                expectedSupport += supportWeights[t];
                expectedOppose += opposeWeights[t];
            }
            assertEq(supportWeight, expectedSupport);
            assertEq(opposeWeight, expectedOppose);
        }
    }

    // voter 集合里不得留下零权重的空票：清零必须删除该票并同步集合。
    function invariant_voterSetsCarryOnlyLiveVotes() public view {
        for (uint256 t = 0; t < TARGET_COUNT; t++) {
            (uint256[] memory voterIds, uint256[] memory supportWeights, uint256[] memory opposeWeights, uint256 total) =
                banSource.votersBySenderId(managerGroupId, targets[t], 0, 10, false);
            assertEq(total, voterIds.length);
            for (uint256 i = 0; i < voterIds.length; i++) {
                assertTrue(supportWeights[i] + opposeWeights[i] != 0);
            }
        }
    }
}
