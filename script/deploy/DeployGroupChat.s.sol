// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {Script} from "@forge-std/Script.sol";
import {console2} from "@forge-std/console2.sol";

import {IMemberNFT} from "@core/interfaces/IMemberNFT.sol";
import {IPhase} from "@core/interfaces/IPhase.sol";
import {IStake} from "@core/interfaces/IStake.sol";
import {IVote} from "@core/interfaces/IVote.sol";
import {IActionTarget} from "@action/interfaces/IActionTarget.sol";

import {GroupAdmin} from "../../src/GroupAdmin.sol";
import {GroupChatBanList} from "../../src/GroupChatBanList.sol";
import {GroupChatDelegate} from "../../src/GroupChatDelegate.sol";
import {GroupChat} from "../../src/GroupChat.sol";
import {GroupMember} from "../../src/GroupMember.sol";
import {IGroupAdmin} from "../../src/interfaces/IGroupAdmin.sol";
import {IGroupChatBanList} from "../../src/interfaces/IGroupChatBanList.sol";
import {IGroupChatDelegate} from "../../src/interfaces/IGroupChatDelegate.sol";
import {IGroupChat} from "../../src/interfaces/IGroupChat.sol";
import {IGroupMember} from "../../src/interfaces/IGroupMember.sol";
import {IAdminBanSource} from "../../src/interfaces/sources/ban/IAdminBanSource.sol";
import {IGovVotedBanSource} from "../../src/interfaces/sources/ban/IGovVotedBanSource.sol";
import {IGroupJoinScopeSource} from "../../src/interfaces/sources/scope/IGroupJoinScopeSource.sol";
import {IGroupMemberScope} from "../../src/interfaces/sources/scope/IGroupMemberScope.sol";
import {IBaseManager} from "../../src/interfaces/managers/IBaseManager.sol";
import {IBaseTokenActionScopeManager} from "../../src/interfaces/managers/IBaseTokenActionScopeManager.sol";
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
    uint256 internal constant DEFAULT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER = 10;
    uint256 internal constant DEFAULT_MAX_CONTENT_LENGTH = 4096;
    uint256 internal constant DEFAULT_MAX_MENTIONED_SENDER_IDS = 32;
    uint256 internal constant PRECISION = 1e18;
    // 当前四类 Manager 的类型码均为 2 字节：2 + 1 分隔符 + 4 位 hex + 4 字节 Test 前缀。
    // 新增更长类型码时同步调整本常量、11_deploy.sh 与 21_check.sh。
    uint256 internal constant MIN_MANAGER_NAME_LENGTH = 11;

    struct Dependencies {
        address groupNft;
        address phase;
        address actionTarget;
        address groupActionExecutor;
    }

    struct CoreAddresses {
        address love20;
        address submit;
        address vote;
        address stake;
        address launch;
    }

    struct DeployConfig {
        address beforePostPlugin;
        address afterPostPlugin;
        uint256 maxContentLength;
        uint256 maxMentionedSenderIds;
        uint256 actionRecentRounds;
        uint256 maxAdminIds;
        uint256 minSupportToOpposeMultiplier;
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
        _validateConfig(deps, config);

        vm.startBroadcast();
        _deployCore(deps, config, deployed);
        _deployManagers(deps, config, deployed);
        vm.stopBroadcast();

        _validateDeployment(deps, config, deployed);
        _logDeploymentSummary(deployed);
    }

    function _loadDependencies() internal view returns (Dependencies memory deps) {
        deps.groupNft = vm.envAddress("MEMBER_NFT_ADDRESS");
        deps.phase = vm.envAddress("PHASE_ADDRESS");
        deps.actionTarget = vm.envAddress("ACTION_TARGET_ADDRESS");
        deps.groupActionExecutor = vm.envAddress("GROUP_ACTION_EXECUTOR_ADDRESS");
        CoreAddresses memory core = CoreAddresses({
            love20: vm.envAddress("LOVE20_TOKEN_ADDRESS"),
            submit: vm.envAddress("SUBMIT_ADDRESS"),
            vote: vm.envAddress("VOTE_ADDRESS"),
            stake: vm.envAddress("STAKE_ADDRESS"),
            launch: vm.envAddress("LAUNCH_ADDRESS")
        });
        _validateDependencies(deps, core);
    }

    function _validateDependencies(Dependencies memory deps, CoreAddresses memory core) internal view {
        require(deps.groupNft.code.length != 0, "MemberNFT must be a deployed contract");
        require(deps.phase.code.length != 0, "Phase must be a deployed contract");
        require(deps.actionTarget.code.length != 0, "ActionTarget must be a deployed contract");
        require(deps.groupActionExecutor.code.length != 0, "GroupActionExecutor must be a deployed contract");
        require(IPhase(deps.phase).ORIGIN_PHASE_BLOCKS() != 0, "Phase.ORIGIN_PHASE_BLOCKS must be > 0");
        require(
            IActionTarget(deps.actionTarget).memberNFTAddress() == deps.groupNft,
            "ActionTarget.memberNFTAddress mismatch"
        );
        require(
            IActionTarget(deps.actionTarget).phaseAddress() == deps.phase,
            "ActionTarget.phaseAddress mismatch"
        );

        address love20 = IMemberNFT(deps.groupNft).LOVE20_TOKEN_ADDRESS();
        require(love20.code.length != 0, "MemberNFT.LOVE20_TOKEN_ADDRESS must be a contract");
        require(love20 == core.love20, "MemberNFT root token mismatch");

        address submit = IActionTarget(deps.actionTarget).submitAddress();
        address vote = IActionTarget(deps.actionTarget).voteAddress();
        require(submit.code.length != 0, "ActionTarget.submitAddress must be a contract");
        require(vote.code.length != 0, "ActionTarget.voteAddress must be a contract");
        address stake = IVote(vote).stakeAddress();
        require(stake.code.length != 0, "Vote.stakeAddress must be a contract");
        address launch = IStake(stake).launchAddress();
        require(launch.code.length != 0, "Stake.launchAddress must be a contract");
        require(submit == core.submit, "ActionTarget.submitAddress mismatch");
        require(vote == core.vote, "ActionTarget.voteAddress mismatch");
        require(stake == core.stake, "Vote.stakeAddress mismatch");
        require(launch == core.launch, "Stake.launchAddress mismatch");
    }

    function _validateConfig(Dependencies memory deps, DeployConfig memory config) internal view {
        require(config.maxContentLength != 0, "GROUP_CHAT_MAX_CONTENT_LENGTH must be > 0");
        require(config.maxMentionedSenderIds != 0, "GROUP_CHAT_MAX_MENTIONED_SENDER_IDS must be > 0");
        require(config.actionRecentRounds != 0, "GROUP_CHAT_ACTION_RECENT_ROUNDS must be > 0");
        require(config.maxAdminIds != 0, "GROUP_CHAT_MAX_ADMIN_IDS must be > 0");
        require(
            config.minSupportToOpposeMultiplier != 0,
            "GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER must be > 0"
        );
        require(config.banThresholdRatio <= PRECISION, "GROUP_CHAT_BAN_THRESHOLD_RATIO must be <= 1e18");
        require(
            IMemberNFT(deps.groupNft).MAX_NAME_LENGTH() >= MIN_MANAGER_NAME_LENGTH,
            "MemberNFT MAX_NAME_LENGTH must be >= 11"
        );
        if (config.beforePostPlugin != address(0)) {
            require(config.beforePostPlugin.code.length != 0, "beforePostPlugin must be a contract");
        }
        if (config.afterPostPlugin != address(0)) {
            require(config.afterPostPlugin.code.length != 0, "afterPostPlugin must be a contract");
        }
    }

    function _loadConfig() internal view returns (DeployConfig memory config) {
        config.beforePostPlugin = vm.envOr("GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS", address(0));
        config.afterPostPlugin = vm.envOr("GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS", address(0));
        config.maxContentLength = vm.envOr("GROUP_CHAT_MAX_CONTENT_LENGTH", DEFAULT_MAX_CONTENT_LENGTH);
        config.maxMentionedSenderIds =
            vm.envOr("GROUP_CHAT_MAX_MENTIONED_SENDER_IDS", DEFAULT_MAX_MENTIONED_SENDER_IDS);
        config.actionRecentRounds = vm.envUint("GROUP_CHAT_ACTION_RECENT_ROUNDS");
        config.maxAdminIds = vm.envOr("GROUP_CHAT_MAX_ADMIN_IDS", DEFAULT_MAX_ADMIN_IDS);
        config.minSupportToOpposeMultiplier =
            vm.envOr("GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER", DEFAULT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER);
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
            new GovVotedBanSource(deps.groupNft, config.minSupportToOpposeMultiplier, config.banThresholdRatio)
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

    function _validateDeployment(
        Dependencies memory deps,
        DeployConfig memory config,
        DeployedAddresses memory deployed
    ) internal view {
        require(
            IGroupChatDelegate(deployed.groupChatDelegate).GROUP_ADDRESS() == deps.groupNft,
            "delegate group mismatch"
        );
        require(
            IGroupAdmin(deployed.groupAdmin).GROUP_DELEGATE_ADDRESS() == deployed.groupChatDelegate,
            "admin delegate mismatch"
        );
        require(IGroupAdmin(deployed.groupAdmin).GROUP_ADDRESS() == deps.groupNft, "admin group mismatch");
        require(IGroupAdmin(deployed.groupAdmin).MAX_ADMIN_IDS() == config.maxAdminIds, "admin max mismatch");
        require(
            IGroupChat(deployed.groupChat).GROUP_ADMIN_ADDRESS() == deployed.groupAdmin,
            "chat admin mismatch"
        );
        require(
            IGroupChat(deployed.groupChat).GROUP_DELEGATE_ADDRESS() == deployed.groupChatDelegate,
            "chat delegate mismatch"
        );
        require(IGroupChat(deployed.groupChat).GROUP_ADDRESS() == deps.groupNft, "chat group mismatch");
        require(IGroupChat(deployed.groupChat).PHASE_ADDRESS() == deps.phase, "chat phase mismatch");
        require(
            IGroupChat(deployed.groupChat).MAX_CONTENT_LENGTH() == config.maxContentLength,
            "chat content max mismatch"
        );
        require(
            IGroupChat(deployed.groupChat).MAX_MENTIONED_SENDER_IDS() == config.maxMentionedSenderIds,
            "chat mention max mismatch"
        );
        require(
            IGroupChatBanList(deployed.groupChatBanList).GROUP_ADMIN_ADDRESS() == deployed.groupAdmin,
            "ban list admin mismatch"
        );
        require(
            IAdminBanSource(deployed.adminBanSource).GROUP_BAN_LIST_ADDRESS() == deployed.groupChatBanList,
            "admin ban list mismatch"
        );
        require(
            IGovVotedBanSource(deployed.govVotedBanSource).GROUP_ADDRESS() == deps.groupNft,
            "gov ban group mismatch"
        );
        require(
            IGovVotedBanSource(deployed.govVotedBanSource).MIN_SUPPORT_TO_OPPOSE_MULTIPLIER()
                == config.minSupportToOpposeMultiplier,
            "gov ban multiplier mismatch"
        );
        require(
            IGovVotedBanSource(deployed.govVotedBanSource).BAN_THRESHOLD_RATIO() == config.banThresholdRatio,
            "gov ban threshold mismatch"
        );
        require(
            IGroupMember(deployed.groupMember).GROUP_ADMIN_ADDRESS() == deployed.groupAdmin,
            "member admin mismatch"
        );
        require(IGroupMember(deployed.groupMember).GROUP_ADDRESS() == deps.groupNft, "member group mismatch");
        require(
            IGroupMemberScope(deployed.groupMemberScope).GROUP_MEMBER_ADDRESS() == deployed.groupMember,
            "member scope mismatch"
        );
        require(
            IGroupJoinScopeSource(deployed.groupJoinScopeSource).GROUP_MEMBER_ADDRESS() == deployed.groupMember,
            "join scope member mismatch"
        );
        require(
            IGroupJoinScopeSource(deployed.groupJoinScopeSource).GROUP_ACTION_EXECUTOR_ADDRESS()
                == deps.groupActionExecutor,
            "join scope executor mismatch"
        );

        _validateManager(deployed.tokenMainManager, deps, config, deployed, false);
        _validateManager(deployed.tokenGovManager, deps, config, deployed, false);
        _validateManager(deployed.tokenActionGovManager, deps, config, deployed, true);
        _validateManager(deployed.tokenActionMainManager, deps, config, deployed, true);
    }

    function _validateManager(
        address manager,
        Dependencies memory deps,
        DeployConfig memory config,
        DeployedAddresses memory deployed,
        bool isAction
    ) internal view {
        require(IBaseManager(manager).GROUP_CHAT_ADDRESS() == deployed.groupChat, "manager chat mismatch");
        require(IBaseManager(manager).GROUP_ADDRESS() == deps.groupNft, "manager group mismatch");
        require(
            IBaseManager(manager).BAN_SOURCE_ADDRESS() == deployed.govVotedBanSource,
            "manager ban source mismatch"
        );
        require(
            IBaseManager(manager).BEFORE_POST_PLUGIN_ADDRESS() == config.beforePostPlugin,
            "manager before plugin mismatch"
        );
        require(
            IBaseManager(manager).AFTER_POST_PLUGIN_ADDRESS() == config.afterPostPlugin,
            "manager after plugin mismatch"
        );
        if (isAction) {
            require(
                IBaseTokenActionScopeManager(manager).RECENT_ROUNDS() == config.actionRecentRounds,
                "manager recent rounds mismatch"
            );
        }
    }

    function _logDeploymentSummary(DeployedAddresses memory deployed) internal pure {
        console2.log("\n=== Deployment Summary ===");
        console2.log("GROUP_CHAT_DELEGATE_ADDRESS=", deployed.groupChatDelegate);
        console2.log("GROUP_ADMIN_ADDRESS=", deployed.groupAdmin);
        console2.log("GROUP_CHAT_ADDRESS=", deployed.groupChat);
        console2.log("GROUP_CHAT_BAN_LIST_ADDRESS=", deployed.groupChatBanList);
        console2.log("ADMIN_BAN_SOURCE_ADDRESS=", deployed.adminBanSource);
        console2.log("GOV_VOTED_BAN_SOURCE_ADDRESS=", deployed.govVotedBanSource);
        console2.log("GROUP_MEMBER_ADDRESS=", deployed.groupMember);
        console2.log("GROUP_MEMBER_SCOPE_ADDRESS=", deployed.groupMemberScope);
        console2.log("GROUP_JOIN_SCOPE_SOURCE_ADDRESS=", deployed.groupJoinScopeSource);
        console2.log("TOKEN_MAIN_MANAGER_ADDRESS=", deployed.tokenMainManager);
        console2.log("TOKEN_GOV_MANAGER_ADDRESS=", deployed.tokenGovManager);
        console2.log("TOKEN_ACTION_GOV_MANAGER_ADDRESS=", deployed.tokenActionGovManager);
        console2.log("TOKEN_ACTION_MAIN_MANAGER_ADDRESS=", deployed.tokenActionMainManager);
    }
}
