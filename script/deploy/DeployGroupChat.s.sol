// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {GroupAdmin} from "../../src/GroupAdmin.sol";
import {GroupChatBanList} from "../../src/GroupChatBanList.sol";
import {GroupChatDelegate} from "../../src/GroupChatDelegate.sol";
import {GroupChat} from "../../src/GroupChat.sol";
import {GroupMember} from "../../src/GroupMember.sol";
import {TokenActionGovManager} from "../../src/managers/TokenActionGovManager.sol";
import {TokenActionMainManager} from "../../src/managers/TokenActionMainManager.sol";
import {TokenGovManager} from "../../src/managers/TokenGovManager.sol";
import {TokenMainManager} from "../../src/managers/TokenMainManager.sol";
import {AdminBanSource} from "../../src/sources/ban/AdminBanSource.sol";
import {GovVotedBanSource} from "../../src/sources/ban/GovVotedBanSource.sol";
import {GroupJoinScopeSource} from "../../src/sources/scope/GroupJoinScopeSource.sol";
import {GroupMemberScope} from "../../src/sources/scope/GroupMemberScope.sol";

contract DeployGroupChat is Script {
    uint256 internal constant DEFAULT_MAX_ADMIN_IDS = 20;
    uint256 internal constant DEFAULT_MIN_SUPPORT_TO_OPPOSE_RATIO = 10;
    uint256 internal constant DEFAULT_MAX_CONTENT_LENGTH = 4096;
    uint256 internal constant DEFAULT_MAX_MENTIONED_SENDER_IDS = 32;

    struct Dependencies {
        address groupNft;
        address phase;
        address actionTarget;
        address groupActionExecutor;
    }

    struct DeployConfig {
        address beforePostPlugin;
        address afterPostPlugin;
        uint256 maxContentLength;
        uint256 maxMentionedSenderIds;
        uint256 actionRecentRounds;
        uint256 maxAdminIds;
        uint256 minSupportToOpposeRatio;
        uint256 banThresholdRatio;
    }

    struct DeployedAddresses {
        address groupChatDelegate;
        address groupAdmin;
        address groupChat;
        address groupChatBanList;
        address adminBanSource;
        address govVotedBanSource;
        address groupMember;
        address groupMemberScope;
        address groupJoinScopeSource;
        address tokenMainManager;
        address tokenGovManager;
        address tokenActionGovManager;
        address tokenActionMainManager;
    }

    function run() external returns (DeployedAddresses memory deployed) {
        require(block.chainid == vm.envUint("CHAIN_ID"), "Chain ID mismatch");

        Dependencies memory deps = _loadDependencies();
        DeployConfig memory config = _loadConfig();

        vm.startBroadcast();
        _deployCore(deps, config, deployed);
        _deployManagers(deps, config, deployed);
        vm.stopBroadcast();

        _logDeploymentSummary(deployed);
    }

    function _loadDependencies() internal view returns (Dependencies memory deps) {
        deps.groupNft = vm.envAddress("GROUP_ADDRESS");
        deps.phase = vm.envAddress("PHASE_ADDRESS");
        deps.actionTarget = vm.envAddress("ACTION_TARGET_ADDRESS");
        deps.groupActionExecutor = vm.envAddress("GROUP_ACTION_EXECUTOR_ADDRESS");
        require(deps.groupNft.code.length != 0, "MemberNFT must be a deployed contract");
        require(deps.phase.code.length != 0, "Phase must be a deployed contract");
        require(deps.actionTarget.code.length != 0, "ActionTarget must be a deployed contract");
        require(deps.groupActionExecutor.code.length != 0, "GroupActionExecutor must be a deployed contract");
    }

    function _loadConfig() internal view returns (DeployConfig memory config) {
        config.beforePostPlugin = vm.envOr("GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS", address(0));
        config.afterPostPlugin = vm.envOr("GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS", address(0));
        config.maxContentLength = vm.envOr("GROUP_CHAT_MAX_CONTENT_LENGTH", DEFAULT_MAX_CONTENT_LENGTH);
        config.maxMentionedSenderIds =
            vm.envOr("GROUP_CHAT_MAX_MENTIONED_SENDER_IDS", DEFAULT_MAX_MENTIONED_SENDER_IDS);
        config.actionRecentRounds = vm.envUint("GROUP_CHAT_ACTION_RECENT_ROUNDS");
        config.maxAdminIds = vm.envOr("GROUP_CHAT_MAX_ADMIN_IDS", DEFAULT_MAX_ADMIN_IDS);
        config.minSupportToOpposeRatio =
            vm.envOr("GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO", DEFAULT_MIN_SUPPORT_TO_OPPOSE_RATIO);
        config.banThresholdRatio = vm.envOr("GROUP_CHAT_BAN_THRESHOLD_RATIO", uint256(3e15));
    }

    function _deployCore(Dependencies memory deps, DeployConfig memory config, DeployedAddresses memory deployed)
        internal
    {
        deployed.groupChatDelegate = address(new GroupChatDelegate(deps.groupNft));
        deployed.groupAdmin = address(new GroupAdmin(deployed.groupChatDelegate, config.maxAdminIds));
        deployed.groupChat = address(
            new GroupChat(deployed.groupAdmin, deps.phase, config.maxContentLength, config.maxMentionedSenderIds)
        );
        deployed.groupChatBanList = address(new GroupChatBanList(deployed.groupAdmin));
        deployed.adminBanSource = address(new AdminBanSource(deployed.groupChatBanList));
        deployed.govVotedBanSource = address(
            new GovVotedBanSource(deps.groupNft, config.minSupportToOpposeRatio, config.banThresholdRatio)
        );
        deployed.groupMember = address(new GroupMember(deployed.groupAdmin));
        deployed.groupMemberScope = address(new GroupMemberScope(deployed.groupMember));
        deployed.groupJoinScopeSource =
            address(new GroupJoinScopeSource(deployed.groupMember, deps.groupActionExecutor));
    }

    function _deployManagers(Dependencies memory deps, DeployConfig memory config, DeployedAddresses memory deployed)
        internal
    {
        deployed.tokenMainManager = address(
            new TokenMainManager(
                deployed.groupChat,
                deployed.govVotedBanSource,
                config.beforePostPlugin,
                config.afterPostPlugin,
                deps.actionTarget
            )
        );
        deployed.tokenGovManager = address(
            new TokenGovManager(
                deployed.groupChat,
                deployed.govVotedBanSource,
                config.beforePostPlugin,
                config.afterPostPlugin,
                deps.actionTarget
            )
        );
        deployed.tokenActionGovManager = address(
            new TokenActionGovManager(
                deployed.groupChat,
                deployed.govVotedBanSource,
                config.beforePostPlugin,
                config.afterPostPlugin,
                deps.actionTarget,
                config.actionRecentRounds
            )
        );
        deployed.tokenActionMainManager = address(
            new TokenActionMainManager(
                deployed.groupChat,
                deployed.govVotedBanSource,
                config.beforePostPlugin,
                config.afterPostPlugin,
                deps.actionTarget,
                config.actionRecentRounds
            )
        );
    }

    function _logDeploymentSummary(DeployedAddresses memory deployed) internal pure {
        console2.log("\n=== Deployment Summary ===");
        console2.log("GROUPCHATDELEGATE_ADDRESS=", deployed.groupChatDelegate);
        console2.log("GROUPADMIN_ADDRESS=", deployed.groupAdmin);
        console2.log("GROUPCHAT_ADDRESS=", deployed.groupChat);
        console2.log("GROUPCHATBANLIST_ADDRESS=", deployed.groupChatBanList);
        console2.log("ADMINBANSOURCE_ADDRESS=", deployed.adminBanSource);
        console2.log("GOVVOTEDBANSOURCE_ADDRESS=", deployed.govVotedBanSource);
        console2.log("GROUPMEMBER_ADDRESS=", deployed.groupMember);
        console2.log("GROUPMEMBERSCOPE_ADDRESS=", deployed.groupMemberScope);
        console2.log("GROUPJOINSCOPESOURCE_ADDRESS=", deployed.groupJoinScopeSource);
        console2.log("TOKENMAINMANAGER_ADDRESS=", deployed.tokenMainManager);
        console2.log("TOKENGOVMANAGER_ADDRESS=", deployed.tokenGovManager);
        console2.log("TOKENACTIONGOVMANAGER_ADDRESS=", deployed.tokenActionGovManager);
        console2.log("TOKENACTIONMAINMANAGER_ADDRESS=", deployed.tokenActionMainManager);
    }
}
