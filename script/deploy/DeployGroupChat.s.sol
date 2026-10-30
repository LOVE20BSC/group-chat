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
import {IManagerBase} from "../../src/interfaces/managers/IManagerBase.sol";
import {ITokenActionScopeManagerBase} from "../../src/interfaces/managers/ITokenActionScopeManagerBase.sol";
import {TokenActionGovManager} from "../../src/managers/TokenActionGovManager.sol";
import {TokenActionMainManager} from "../../src/managers/TokenActionMainManager.sol";
import {TokenGovManager} from "../../src/managers/TokenGovManager.sol";
import {TokenMainManager} from "../../src/managers/TokenMainManager.sol";
import {AdminBanSource} from "../../src/sources/ban/AdminBanSource.sol";
import {GovVotedBanSource} from "../../src/sources/ban/GovVotedBanSource.sol";
import {GroupJoinScopeSource} from "../../src/sources/scope/GroupJoinScopeSource.sol";
import {GroupMemberScope} from "../../src/sources/scope/GroupMemberScope.sol";

contract DeployGroupChat is Script {
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant LONGEST_MANAGER_TYPE_CODE_BYTES = 2;
    uint256 internal constant GROUP_NAME_SEPARATOR_BYTES = 1;
    uint256 internal constant GROUP_NAME_RANDOM_HEX_LENGTH = 4;
    uint256 internal constant GROUP_NAME_TEST_PREFIX_BYTES = 4;

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
        uint256 chainId;
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
        Dependencies memory deps = _loadDependencies();
        CoreAddresses memory core = _loadCoreAddresses();
        DeployConfig memory config = _loadConfig();
        _validateDependencies(deps, core);
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
    }

    function _loadCoreAddresses() internal view returns (CoreAddresses memory core) {
        core = CoreAddresses({
            love20: vm.envAddress("LOVE20_TOKEN_ADDRESS"),
            submit: vm.envAddress("SUBMIT_ADDRESS"),
            vote: vm.envAddress("VOTE_ADDRESS"),
            stake: vm.envAddress("STAKE_ADDRESS"),
            launch: vm.envAddress("LAUNCH_ADDRESS")
        });
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
        address stake = IVote(vote).STAKE_ADDRESS();
        require(stake.code.length != 0, "Vote.stakeAddress must be a contract");
        address launch = IStake(stake).LAUNCH_ADDRESS();
        require(launch.code.length != 0, "Stake.launchAddress must be a contract");
        require(submit == core.submit, "ActionTarget.submitAddress mismatch");
        require(vote == core.vote, "ActionTarget.voteAddress mismatch");
        require(stake == core.stake, "Vote.stakeAddress mismatch");
        require(launch == core.launch, "Stake.launchAddress mismatch");
    }

    function _validateConfig(Dependencies memory deps, DeployConfig memory config) internal view {
        require(block.chainid == config.chainId, "Chain ID mismatch");
        require(config.maxContentLength != 0, "GROUP_CHAT_MAX_CONTENT_LENGTH must be > 0");
        require(config.maxMentionedSenderIds != 0, "GROUP_CHAT_MAX_MENTIONED_SENDER_IDS must be > 0");
        require(config.actionRecentRounds != 0, "GROUP_CHAT_ACTION_RECENT_ROUNDS must be > 0");
        require(config.maxAdminIds != 0, "GROUP_CHAT_MAX_ADMIN_IDS must be > 0");
        require(
            config.minSupportToOpposeMultiplier != 0,
            "GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER must be > 0"
        );
        require(config.banThresholdRatio <= PRECISION, "GROUP_CHAT_BAN_THRESHOLD_RATIO must be <= 1e18");
        uint256 minNameLength = LONGEST_MANAGER_TYPE_CODE_BYTES + GROUP_NAME_SEPARATOR_BYTES
            + GROUP_NAME_RANDOM_HEX_LENGTH + GROUP_NAME_TEST_PREFIX_BYTES;
        require(
            IMemberNFT(deps.groupNft).MAX_NAME_LENGTH() >= minNameLength,
            string.concat("MemberNFT MAX_NAME_LENGTH must be >= ", vm.toString(minNameLength))
        );
        if (config.beforePostPlugin != address(0)) {
            require(config.beforePostPlugin.code.length != 0, "beforePostPlugin must be a contract");
        }
        if (config.afterPostPlugin != address(0)) {
            require(config.afterPostPlugin.code.length != 0, "afterPostPlugin must be a contract");
        }
    }

    // 插件槽位是必填键：零地址=不挂载，键缺失即 revert。「没配」与「选了不挂载」不能共用同一种表示，
    // 否则键名拼错会静默部署出一个没有插件的群。
    function _loadConfig() internal view returns (DeployConfig memory config) {
        config.chainId = vm.envUint("CHAIN_ID");
        config.beforePostPlugin = vm.envAddress("GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS");
        config.afterPostPlugin = vm.envAddress("GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS");
        config.maxContentLength = vm.envUint("GROUP_CHAT_MAX_CONTENT_LENGTH");
        config.maxMentionedSenderIds = vm.envUint("GROUP_CHAT_MAX_MENTIONED_SENDER_IDS");
        config.actionRecentRounds = vm.envUint("GROUP_CHAT_ACTION_RECENT_ROUNDS");
        config.maxAdminIds = vm.envUint("GROUP_CHAT_MAX_ADMIN_IDS");
        config.minSupportToOpposeMultiplier = vm.envUint("GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER");
        config.banThresholdRatio = vm.envUint("GROUP_CHAT_BAN_THRESHOLD_RATIO");
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
        require(IManagerBase(manager).GROUP_CHAT_ADDRESS() == deployed.groupChat, "manager chat mismatch");
        require(IManagerBase(manager).GROUP_ADDRESS() == deps.groupNft, "manager group mismatch");
        require(
            IManagerBase(manager).BAN_SOURCE_ADDRESS() == deployed.govVotedBanSource,
            "manager ban source mismatch"
        );
        require(
            IManagerBase(manager).BEFORE_POST_PLUGIN_ADDRESS() == config.beforePostPlugin,
            "manager before plugin mismatch"
        );
        require(
            IManagerBase(manager).AFTER_POST_PLUGIN_ADDRESS() == config.afterPostPlugin,
            "manager after plugin mismatch"
        );
        if (isAction) {
            require(
                ITokenActionScopeManagerBase(manager).RECENT_ROUNDS() == config.actionRecentRounds,
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
