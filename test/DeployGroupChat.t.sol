// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {DeployGroupChat} from "../script/DeployGroupChat.s.sol";
import {GroupAdmin} from "../src/GroupAdmin.sol";
import {GroupBanList} from "../src/GroupBanList.sol";
import {GroupMember} from "../src/GroupMember.sol";
import {IGroupChat} from "../src/interfaces/IGroupChat.sol";
import {IBaseManager} from "../src/interfaces/managers/IBaseManager.sol";
import {BaseTokenActionScopeManager} from "../src/managers/BaseTokenActionScopeManager.sol";
import {BaseTokenScopeManager} from "../src/managers/BaseTokenScopeManager.sol";
import {TokenActionGovManager} from "../src/managers/TokenActionGovManager.sol";
import {TokenActionMainManager} from "../src/managers/TokenActionMainManager.sol";
import {AdminBanSource} from "../src/sources/ban/AdminBanSource.sol";
import {GovVotedBanSource} from "../src/sources/ban/GovVotedBanSource.sol";
import {GroupJoinScopeSource} from "../src/sources/scope/GroupJoinScopeSource.sol";
import {GroupMemberScope} from "../src/sources/scope/GroupMemberScope.sol";

import {MockGroupDefaults} from "./mocks/MockGroupDefaults.sol";
import {MockGroupDelegate} from "./mocks/MockGroupDelegate.sol";
import {MockLOVE20Group} from "./mocks/MockLOVE20Group.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {TestBase} from "./utils/TestBase.sol";

contract DeployMockGroupJoin {
    function gTokenAddressesByGroupIdByAccountCount(uint256, address) external pure returns (uint256) {
        return 0;
    }
}

contract DeployGroupChatHarness is DeployGroupChat {
    function configFromCoreJoinForTest(
        address groupDefaults,
        address groupDelegate,
        address extensionCenter,
        address groupJoin,
        address beforePostPlugin,
        address afterPostPlugin,
        uint256 maxContentLength,
        uint256 maxMentionedSenderIds,
        uint256 actionRecentRounds,
        uint256 maxAdminIds,
        uint256 minSupportToOpposeRatio,
        uint256 banThresholdRatio
    ) external view returns (DeployConfig memory) {
        return _configFromCoreJoin(
            groupDefaults,
            groupDelegate,
            extensionCenter,
            groupJoin,
            beforePostPlugin,
            afterPostPlugin,
            maxContentLength,
            maxMentionedSenderIds,
            actionRecentRounds,
            maxAdminIds,
            minSupportToOpposeRatio,
            banThresholdRatio
        );
    }

    function deployForTest(DeployConfig memory config) external returns (DeployedAddresses memory) {
        return _deploy(config);
    }

    function addressFileContentForTest(DeployConfig memory config, DeployedAddresses memory deployed)
        external
        pure
        returns (string memory)
    {
        return _addressFileContent(config, deployed);
    }
}

contract DeployGroupChatTest is TestBase {
    uint256 internal constant BAN_THRESHOLD_RATIO = 3e15;
    uint256 internal constant MIN_SUPPORT_TO_OPPOSE_RATIO = 10;
    uint256 internal constant MAX_CONTENT_LENGTH = 4096;
    uint256 internal constant MAX_MENTIONED_SENDER_IDS = 32;
    uint256 internal constant MAX_ADMIN_IDS = 20;

    MockLOVE20Group internal groupNft;
    MockGroupDefaults internal groupDefaults;
    MockGroupDelegate internal groupDelegate;
    MockLOVE20Protocols internal protocol;
    DeployMockGroupJoin internal groupJoin;
    DeployGroupChatHarness internal deployer;

    function setUp() public {
        groupNft = new MockLOVE20Group();
        groupDefaults = new MockGroupDefaults(address(groupNft));
        groupDelegate = new MockGroupDelegate(address(groupNft));
        protocol = new MockLOVE20Protocols();
        groupJoin = new DeployMockGroupJoin();
        deployer = new DeployGroupChatHarness();
    }

    function testT140_deploysSourcesManagersAndWiresDependencies() public {
        DeployGroupChat.DeployConfig memory config = DeployGroupChat.DeployConfig({
            groupDefaults: address(groupDefaults),
            groupDelegate: address(groupDelegate),
            extensionCenter: address(protocol),
            groupJoin: address(groupJoin),
            beforePostPlugin: address(0),
            afterPostPlugin: address(0),
            originBlocks: 100,
            phaseBlocks: 25,
            maxContentLength: MAX_CONTENT_LENGTH,
            maxMentionedSenderIds: MAX_MENTIONED_SENDER_IDS,
            actionRecentRounds: 3,
            maxAdminIds: MAX_ADMIN_IDS,
            minSupportToOpposeRatio: MIN_SUPPORT_TO_OPPOSE_RATIO,
            banThresholdRatio: BAN_THRESHOLD_RATIO
        });

        DeployGroupChat.DeployedAddresses memory deployed = deployer.deployForTest(config);

        assertTrue(deployed.groupChat.code.length != 0);
        assertTrue(deployed.groupAdmin.code.length != 0);
        assertTrue(deployed.groupBanList.code.length != 0);
        assertTrue(deployed.adminBanSource.code.length != 0);
        assertTrue(deployed.govVotedBanSource.code.length != 0);
        assertTrue(deployed.groupMember.code.length != 0);
        assertTrue(deployed.groupMemberScope.code.length != 0);
        assertTrue(deployed.groupJoinScopeSource.code.length != 0);
        assertTrue(deployed.tokenMainManager.code.length != 0);
        assertTrue(deployed.tokenGovManager.code.length != 0);
        assertTrue(deployed.tokenActionGovManager.code.length != 0);
        assertTrue(deployed.tokenActionMainManager.code.length != 0);

        assertEq(IGroupChat(deployed.groupChat).GROUP_ADMIN_ADDRESS(), deployed.groupAdmin);
        assertEq(IGroupChat(deployed.groupChat).GROUP_DEFAULTS_ADDRESS(), address(groupDefaults));
        assertEq(IGroupChat(deployed.groupChat).GROUP_DELEGATE_ADDRESS(), address(groupDelegate));
        assertEq(IGroupChat(deployed.groupChat).GROUP_ADDRESS(), address(groupNft));
        assertEq(IGroupChat(deployed.groupChat).originBlocks(), 100);
        assertEq(IGroupChat(deployed.groupChat).phaseBlocks(), 25);
        assertEq(IGroupChat(deployed.groupChat).MAX_CONTENT_LENGTH(), MAX_CONTENT_LENGTH);
        assertEq(IGroupChat(deployed.groupChat).MAX_MENTIONED_SENDER_IDS(), MAX_MENTIONED_SENDER_IDS);

        assertEq(GroupAdmin(deployed.groupAdmin).GROUP_DEFAULTS_ADDRESS(), address(groupDefaults));
        assertEq(GroupAdmin(deployed.groupAdmin).GROUP_DELEGATE_ADDRESS(), address(groupDelegate));
        assertEq(GroupAdmin(deployed.groupAdmin).GROUP_ADDRESS(), address(groupNft));
        assertEq(GroupAdmin(deployed.groupAdmin).MAX_ADMIN_IDS(), MAX_ADMIN_IDS);
        assertEq(GroupBanList(deployed.groupBanList).GROUP_ADMIN_ADDRESS(), deployed.groupAdmin);
        assertEq(AdminBanSource(deployed.adminBanSource).GROUP_BAN_LIST_ADDRESS(), deployed.groupBanList);
        assertEq(GovVotedBanSource(deployed.govVotedBanSource).GROUP_ADDRESS(), address(groupNft));
        assertEq(GovVotedBanSource(deployed.govVotedBanSource).PRECISION(), 1e18);
        assertEq(
            GovVotedBanSource(deployed.govVotedBanSource).MIN_SUPPORT_TO_OPPOSE_RATIO(),
            MIN_SUPPORT_TO_OPPOSE_RATIO
        );
        assertEq(GovVotedBanSource(deployed.govVotedBanSource).BAN_THRESHOLD_RATIO(), BAN_THRESHOLD_RATIO);
        assertEq(GroupMember(deployed.groupMember).GROUP_ADMIN_ADDRESS(), deployed.groupAdmin);
        assertEq(GroupMember(deployed.groupMember).GROUP_ADDRESS(), address(groupNft));
        assertEq(GroupMemberScope(deployed.groupMemberScope).GROUP_MEMBER_ADDRESS(), deployed.groupMember);
        assertEq(GroupJoinScopeSource(deployed.groupJoinScopeSource).GROUP_MEMBER_ADDRESS(), deployed.groupMember);
        assertEq(GroupJoinScopeSource(deployed.groupJoinScopeSource).GROUP_JOIN_ADDRESS(), address(groupJoin));

        _assertManagerCommon(deployed.tokenMainManager, deployed);
        _assertManagerCommon(deployed.tokenGovManager, deployed);
        _assertManagerCommon(deployed.tokenActionGovManager, deployed);
        _assertManagerCommon(deployed.tokenActionMainManager, deployed);

        assertEq(BaseTokenScopeManager(deployed.tokenMainManager).EXTENSION_CENTER_ADDRESS(), address(protocol));
        assertEq(BaseTokenScopeManager(deployed.tokenGovManager).EXTENSION_CENTER_ADDRESS(), address(protocol));
        assertEq(
            BaseTokenActionScopeManager(deployed.tokenActionGovManager).EXTENSION_CENTER_ADDRESS(), address(protocol)
        );
        assertEq(
            BaseTokenActionScopeManager(deployed.tokenActionMainManager).EXTENSION_CENTER_ADDRESS(), address(protocol)
        );

        _assertTokenMainManagerDerivedAddressGettersHidden(deployed.tokenMainManager);
        _assertTokenMainManagerDerivedAddressGettersHidden(deployed.tokenGovManager);
        _assertActionManagerDerivedAddressGettersHidden(deployed.tokenActionGovManager);
        _assertActionManagerDerivedAddressGettersHidden(deployed.tokenActionMainManager);

        assertEq(TokenActionGovManager(deployed.tokenActionGovManager).RECENT_ROUNDS(), 3);
        assertEq(TokenActionMainManager(deployed.tokenActionMainManager).RECENT_ROUNDS(), 3);
    }

    function testT140B_configUsesCoreJoinRoundParameters() public {
        protocol.setPhase(321, 44);

        DeployGroupChat.DeployConfig memory config = deployer.configFromCoreJoinForTest(
            address(groupDefaults),
            address(groupDelegate),
            address(protocol),
            address(groupJoin),
            address(0xBEEF),
            address(0xCAFE),
            MAX_CONTENT_LENGTH,
            MAX_MENTIONED_SENDER_IDS,
            7,
            MAX_ADMIN_IDS,
            MIN_SUPPORT_TO_OPPOSE_RATIO,
            BAN_THRESHOLD_RATIO
        );

        assertEq(config.groupDefaults, address(groupDefaults));
        assertEq(config.groupDelegate, address(groupDelegate));
        assertEq(config.extensionCenter, address(protocol));
        assertEq(config.groupJoin, address(groupJoin));
        assertEq(config.beforePostPlugin, address(0xBEEF));
        assertEq(config.afterPostPlugin, address(0xCAFE));
        assertEq(config.originBlocks, 321);
        assertEq(config.phaseBlocks, 44);
        assertEq(config.maxContentLength, MAX_CONTENT_LENGTH);
        assertEq(config.maxMentionedSenderIds, MAX_MENTIONED_SENDER_IDS);
        assertEq(config.actionRecentRounds, 7);
        assertEq(config.maxAdminIds, MAX_ADMIN_IDS);
        assertEq(config.minSupportToOpposeRatio, MIN_SUPPORT_TO_OPPOSE_RATIO);
        assertEq(config.banThresholdRatio, BAN_THRESHOLD_RATIO);
    }

    function testT141_addressFileContentIncludesOnlyGroupChatDeploymentFields() public view {
        DeployGroupChat.DeployConfig memory config = DeployGroupChat.DeployConfig({
            groupDefaults: address(groupDefaults),
            groupDelegate: address(groupDelegate),
            extensionCenter: address(protocol),
            groupJoin: address(groupJoin),
            beforePostPlugin: address(0xBEEF),
            afterPostPlugin: address(0xCAFE),
            originBlocks: 123,
            phaseBlocks: 456,
            maxContentLength: MAX_CONTENT_LENGTH,
            maxMentionedSenderIds: MAX_MENTIONED_SENDER_IDS,
            actionRecentRounds: 7,
            maxAdminIds: MAX_ADMIN_IDS,
            minSupportToOpposeRatio: MIN_SUPPORT_TO_OPPOSE_RATIO,
            banThresholdRatio: BAN_THRESHOLD_RATIO
        });
        DeployGroupChat.DeployedAddresses memory deployed = DeployGroupChat.DeployedAddresses({
            groupChat: address(0x101),
            groupAdmin: address(0x102),
            groupBanList: address(0x103),
            adminBanSource: address(0x104),
            govVotedBanSource: address(0x105),
            groupMember: address(0x106),
            groupMemberScope: address(0x107),
            groupJoinScopeSource: address(0x108),
            tokenMainManager: address(0x109),
            tokenGovManager: address(0x10A),
            tokenActionGovManager: address(0x10B),
            tokenActionMainManager: address(0x10C)
        });

        string memory content = deployer.addressFileContentForTest(config, deployed);

        _assertContains(content, "groupAdminAddress=");
        _assertContains(content, "groupBanListAddress=");
        _assertContains(content, "adminBanSourceAddress=");
        _assertContains(content, "govVotedBanSourceAddress=");
        _assertContains(content, "groupMemberAddress=");
        _assertContains(content, "groupMemberScopeAddress=");
        _assertContains(content, "groupJoinScopeSourceAddress=");
        _assertContains(content, "groupChatAddress=");
        _assertContains(content, "tokenMainManagerAddress=");
        _assertContains(content, "tokenGovManagerAddress=");
        _assertContains(content, "tokenActionGovManagerAddress=");
        _assertContains(content, "tokenActionMainManagerAddress=");
        _assertNotContains(content, "groupDefaultsAddress=");
        _assertNotContains(content, "groupDelegateAddress=");
        _assertNotContains(content, "extensionCenterAddress=");
        _assertNotContains(content, "groupJoinAddress=");
        _assertNotContains(content, "groupChatBeforePostPluginAddress=");
        _assertNotContains(content, "groupChatAfterPostPluginAddress=");
        _assertNotContains(content, "originBlocks=");
        _assertNotContains(content, "phaseBlocks=");
        _assertNotContains(content, "maxAdminIds=");
    }

    function _assertManagerCommon(address manager, DeployGroupChat.DeployedAddresses memory deployed) internal view {
        assertEq(IBaseManager(manager).GROUP_CHAT_ADDRESS(), deployed.groupChat);
        assertEq(IBaseManager(manager).BAN_SOURCE_ADDRESS(), deployed.govVotedBanSource);
        assertEq(IBaseManager(manager).BEFORE_POST_PLUGIN_ADDRESS(), address(0));
        assertEq(IBaseManager(manager).AFTER_POST_PLUGIN_ADDRESS(), address(0));
    }

    function _assertTokenMainManagerDerivedAddressGettersHidden(address manager) internal {
        _expectUnknownSelector(manager, abi.encodeWithSignature("STAKE_ADDRESS()"));
        _expectUnknownSelector(manager, abi.encodeWithSignature("LAUNCH_ADDRESS()"));
        _expectUnknownSelector(manager, abi.encodeWithSignature("JOIN_ADDRESS()"));
        _expectUnknownSelector(manager, abi.encodeWithSignature("VOTE_ADDRESS()"));
    }

    function _assertActionManagerDerivedAddressGettersHidden(address manager) internal {
        _expectUnknownSelector(manager, abi.encodeWithSignature("STAKE_ADDRESS()"));
        _expectUnknownSelector(manager, abi.encodeWithSignature("LAUNCH_ADDRESS()"));
        _expectUnknownSelector(manager, abi.encodeWithSignature("VOTE_ADDRESS()"));
        _expectUnknownSelector(manager, abi.encodeWithSignature("JOIN_ADDRESS()"));
    }

    function _expectUnknownSelector(address target, bytes memory data) internal {
        (bool ok,) = target.call(data);
        assertTrue(!ok);
    }

    function _assertContains(string memory haystack, string memory needle) internal pure {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        require(n.length != 0 && h.length >= n.length, "ASSERT_CONTAINS");

        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool matched = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                return;
            }
        }

        revert("ASSERT_CONTAINS");
    }

    function _assertNotContains(string memory haystack, string memory needle) internal pure {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        require(n.length != 0, "ASSERT_NOT_CONTAINS_EMPTY");

        if (h.length < n.length) {
            return;
        }

        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool matched = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            require(!matched, "ASSERT_NOT_CONTAINS");
        }
    }
}
