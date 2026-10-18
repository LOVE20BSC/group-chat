// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../src/GroupAdmin.sol";

import {GroupChatBanList} from "../src/GroupChatBanList.sol";
import {GroupChat} from "../src/GroupChat.sol";
import {GroupMember} from "../src/GroupMember.sol";
import {TokenActionGovManager} from "../src/managers/TokenActionGovManager.sol";
import {TokenActionMainManager} from "../src/managers/TokenActionMainManager.sol";
import {TokenGovManager} from "../src/managers/TokenGovManager.sol";
import {TokenMainManager} from "../src/managers/TokenMainManager.sol";
import {AdminBanSource} from "../src/sources/ban/AdminBanSource.sol";
import {GovVotedBanSource} from "../src/sources/ban/GovVotedBanSource.sol";
import {GroupJoinScopeSource} from "../src/sources/scope/GroupJoinScopeSource.sol";
import {GroupMemberScope} from "../src/sources/scope/GroupMemberScope.sol";
import {ScriptBase} from "./ScriptBase.sol";

contract DeployGroupChat is ScriptBase {
    uint256 internal constant DEFAULT_MAX_ADMIN_IDS = 20;
    uint256 internal constant DEFAULT_MIN_SUPPORT_TO_OPPOSE_RATIO = 10;
    uint256 internal constant DEFAULT_MAX_CONTENT_LENGTH = 4096;
    uint256 internal constant DEFAULT_MAX_MENTIONED_SENDER_IDS = 32;

    struct DeployConfig {
        address groupDelegate;
        address phaseAddress;
        address actionTarget;
        address groupActionExecutor;
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
        address groupChat;
        address groupAdmin;
        address groupBanList;
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

    function run() external {
        DeployConfig memory config = _loadConfig();

        vm.startBroadcast();
        DeployedAddresses memory deployed = _deploy(config);
        vm.stopBroadcast();

        string memory network = vm.envString("network");
        string memory dir = string.concat("script/network/", network);
        vm.createDir(dir, true);
        _writeAddressFile(dir, deployed);
    }

    function _loadConfig() internal returns (DeployConfig memory config) {
        config.groupDelegate = vm.envAddress("GROUP_DELEGATE_ADDRESS");
        config.phaseAddress = vm.envAddress("PHASE_ADDRESS");
        config.actionTarget = vm.envAddress("ACTION_TARGET_ADDRESS");
        config.groupActionExecutor = vm.envAddress("GROUP_ACTION_EXECUTOR_ADDRESS");
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

    function _deploy(DeployConfig memory config) internal returns (DeployedAddresses memory deployed) {
        _deployCore(config, deployed);
        _deployManagers(config, deployed);
    }

    function _deployCore(DeployConfig memory config, DeployedAddresses memory deployed) internal {
        deployed.groupAdmin = address(new GroupAdmin(config.groupDelegate, config.maxAdminIds));
        deployed.groupChat = address(
            new GroupChat(
                deployed.groupAdmin, config.phaseAddress, config.maxContentLength, config.maxMentionedSenderIds
            )
        );
        deployed.groupBanList = address(new GroupChatBanList(deployed.groupAdmin));
        deployed.adminBanSource = address(new AdminBanSource(deployed.groupBanList));
        deployed.govVotedBanSource = address(
            new GovVotedBanSource(
                GroupChat(deployed.groupChat).GROUP_ADDRESS(),
                config.minSupportToOpposeRatio,
                config.banThresholdRatio
            )
        );
        deployed.groupMember = address(new GroupMember(deployed.groupAdmin));
        deployed.groupMemberScope = address(new GroupMemberScope(deployed.groupMember));
        deployed.groupJoinScopeSource = address(new GroupJoinScopeSource(deployed.groupMember, config.groupActionExecutor));
    }

    function _deployManagers(DeployConfig memory config, DeployedAddresses memory deployed) internal {
        deployed.tokenMainManager = address(
            new TokenMainManager(
                deployed.groupChat,
                deployed.govVotedBanSource,
                config.beforePostPlugin,
                config.afterPostPlugin,
                config.actionTarget
            )
        );
        deployed.tokenGovManager = address(
            new TokenGovManager(
                deployed.groupChat,
                deployed.govVotedBanSource,
                config.beforePostPlugin,
                config.afterPostPlugin,
                config.actionTarget
            )
        );
        deployed.tokenActionGovManager = address(
            new TokenActionGovManager(
                deployed.groupChat,
                deployed.govVotedBanSource,
                config.beforePostPlugin,
                config.afterPostPlugin,
                config.actionTarget,
                config.actionRecentRounds
            )
        );
        deployed.tokenActionMainManager = address(
            new TokenActionMainManager(
                deployed.groupChat,
                deployed.govVotedBanSource,
                config.beforePostPlugin,
                config.afterPostPlugin,
                config.actionTarget,
                config.actionRecentRounds
            )
        );
    }

    function _writeAddressFile(string memory dir, DeployedAddresses memory deployed) internal {
        string memory addressFile = string.concat(dir, "/address.group.chat.params");
        vm.writeFile(addressFile, _addressFileContent(deployed));
    }

    function _addressFileContent(DeployedAddresses memory deployed) internal pure returns (string memory) {
        string memory content = _addressLine("groupAdminAddress", deployed.groupAdmin);
        content = string.concat(content, _addressLine("groupBanListAddress", deployed.groupBanList));
        content = string.concat(content, _addressLine("adminBanSourceAddress", deployed.adminBanSource));
        content = string.concat(content, _addressLine("govVotedBanSourceAddress", deployed.govVotedBanSource));
        content = string.concat(content, _addressLine("groupMemberAddress", deployed.groupMember));
        content = string.concat(content, _addressLine("groupMemberScopeAddress", deployed.groupMemberScope));
        content = string.concat(content, _addressLine("groupJoinScopeSourceAddress", deployed.groupJoinScopeSource));
        content = string.concat(content, _addressLine("groupChatAddress", deployed.groupChat));
        content = string.concat(content, _addressLine("tokenMainManagerAddress", deployed.tokenMainManager));
        content = string.concat(content, _addressLine("tokenGovManagerAddress", deployed.tokenGovManager));
        content = string.concat(content, _addressLine("tokenActionGovManagerAddress", deployed.tokenActionGovManager));
        content = string.concat(content, _addressLine("tokenActionMainManagerAddress", deployed.tokenActionMainManager));
        return content;
    }

    function _addressLine(string memory key, address value) internal pure returns (string memory) {
        return string.concat(key, "=", vm.toString(value), "\n");
    }
}
