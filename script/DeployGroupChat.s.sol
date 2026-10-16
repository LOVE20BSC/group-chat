// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupAdmin} from "../src/GroupAdmin.sol";

import {GroupBanList} from "../src/GroupBanList.sol";
import {GroupChat} from "../src/GroupChat.sol";
import {GroupMember} from "../src/GroupMember.sol";
import {IExtensionCenter} from "../src/interfaces/external/IExtensionCenter.sol";
import {ILOVE20Join} from "../src/interfaces/external/ILOVE20Join.sol";
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
        address groupDefaults;
        address groupDelegate;
        address extensionCenter;
        address groupJoin;
        address beforePostPlugin;
        address afterPostPlugin;
        uint256 originBlocks;
        uint256 phaseBlocks;
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
        address groupJoin = vm.envAddress("GROUP_JOIN_ADDRESS");
        DeployConfig memory config = _configFromCoreJoin(
            vm.envAddress("GROUP_DEFAULTS_ADDRESS"),
            vm.envAddress("GROUP_DELEGATE_ADDRESS"),
            vm.envAddress("EXTENSION_CENTER_ADDRESS"),
            groupJoin,
            vm.envOr("GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS", address(0)),
            vm.envOr("GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS", address(0)),
            vm.envOr("GROUP_CHAT_MAX_CONTENT_LENGTH", DEFAULT_MAX_CONTENT_LENGTH),
            vm.envOr("GROUP_CHAT_MAX_MENTIONED_SENDER_IDS", DEFAULT_MAX_MENTIONED_SENDER_IDS),
            vm.envUint("GROUP_CHAT_ACTION_RECENT_ROUNDS"),
            vm.envOr("GROUP_CHAT_MAX_ADMIN_IDS", DEFAULT_MAX_ADMIN_IDS),
            vm.envOr("GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO", DEFAULT_MIN_SUPPORT_TO_OPPOSE_RATIO),
            vm.envOr("GROUP_CHAT_BAN_THRESHOLD_RATIO", uint256(3e15))
        );

        vm.startBroadcast();
        DeployedAddresses memory deployed = _deploy(config);
        vm.stopBroadcast();

        string memory network = vm.envString("network");
        string memory dir = string.concat("script/network/", network);
        vm.createDir(dir, true);
        _writeAddressFile(dir, config, deployed);
    }

    function _configFromCoreJoin(
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
    ) internal view returns (DeployConfig memory) {
        address coreJoin = IExtensionCenter(extensionCenter).joinAddress();
        return DeployConfig({
            groupDefaults: groupDefaults,
            groupDelegate: groupDelegate,
            extensionCenter: extensionCenter,
            groupJoin: groupJoin,
            beforePostPlugin: beforePostPlugin,
            afterPostPlugin: afterPostPlugin,
            originBlocks: ILOVE20Join(coreJoin).originBlocks(),
            phaseBlocks: ILOVE20Join(coreJoin).phaseBlocks(),
            maxContentLength: maxContentLength,
            maxMentionedSenderIds: maxMentionedSenderIds,
            actionRecentRounds: actionRecentRounds,
            maxAdminIds: maxAdminIds,
            minSupportToOpposeRatio: minSupportToOpposeRatio,
            banThresholdRatio: banThresholdRatio
        });
    }

    function _deploy(DeployConfig memory config) internal returns (DeployedAddresses memory deployed) {
        deployed.groupAdmin = address(new GroupAdmin(config.groupDefaults, config.groupDelegate, config.maxAdminIds));
        GroupChat groupChat = new GroupChat(
            deployed.groupAdmin,
            config.originBlocks,
            config.phaseBlocks,
            config.maxContentLength,
            config.maxMentionedSenderIds
        );
        deployed.groupChat = address(groupChat);
        deployed.groupBanList = address(new GroupBanList(deployed.groupAdmin));
        deployed.adminBanSource = address(new AdminBanSource(deployed.groupBanList));
        deployed.govVotedBanSource = address(
            new GovVotedBanSource(
                groupChat.GROUP_ADDRESS(), config.minSupportToOpposeRatio, config.banThresholdRatio
            )
        );
        deployed.groupMember = address(new GroupMember(deployed.groupAdmin));
        deployed.groupMemberScope = address(new GroupMemberScope(deployed.groupMember));
        deployed.groupJoinScopeSource = address(new GroupJoinScopeSource(deployed.groupMember, config.groupJoin));

        TokenMainManager tokenMainManager = new TokenMainManager(
            address(groupChat),
            deployed.govVotedBanSource,
            config.beforePostPlugin,
            config.afterPostPlugin,
            config.extensionCenter
        );
        deployed.tokenMainManager = address(tokenMainManager);
        TokenGovManager tokenGovManager = new TokenGovManager(
            address(groupChat),
            deployed.govVotedBanSource,
            config.beforePostPlugin,
            config.afterPostPlugin,
            config.extensionCenter
        );
        deployed.tokenGovManager = address(tokenGovManager);
        TokenActionGovManager tokenActionGovManager = new TokenActionGovManager(
            address(groupChat),
            deployed.govVotedBanSource,
            config.beforePostPlugin,
            config.afterPostPlugin,
            config.extensionCenter,
            config.actionRecentRounds
        );
        deployed.tokenActionGovManager = address(tokenActionGovManager);
        TokenActionMainManager tokenActionMainManager = new TokenActionMainManager(
            address(groupChat),
            deployed.govVotedBanSource,
            config.beforePostPlugin,
            config.afterPostPlugin,
            config.extensionCenter,
            config.actionRecentRounds
        );
        deployed.tokenActionMainManager = address(tokenActionMainManager);
    }

    function _writeAddressFile(string memory dir, DeployConfig memory config, DeployedAddresses memory deployed)
        internal
    {
        string memory addressFile = string.concat(dir, "/address.group.chat.params");
        vm.writeFile(addressFile, _addressFileContent(config, deployed));
    }

    function _addressFileContent(DeployConfig memory, DeployedAddresses memory deployed)
        internal
        pure
        returns (string memory)
    {
        string memory content = string.concat(
            _addressLine("groupAdminAddress", deployed.groupAdmin),
            _addressLine("groupBanListAddress", deployed.groupBanList),
            _addressLine("adminBanSourceAddress", deployed.adminBanSource),
            _addressLine("govVotedBanSourceAddress", deployed.govVotedBanSource),
            _addressLine("groupMemberAddress", deployed.groupMember),
            _addressLine("groupMemberScopeAddress", deployed.groupMemberScope),
            _addressLine("groupJoinScopeSourceAddress", deployed.groupJoinScopeSource)
        );
        content = string.concat(
            content,
            _addressLine("groupChatAddress", deployed.groupChat),
            _addressLine("tokenMainManagerAddress", deployed.tokenMainManager),
            _addressLine("tokenGovManagerAddress", deployed.tokenGovManager)
        );
        content = string.concat(
            content,
            _addressLine("tokenActionGovManagerAddress", deployed.tokenActionGovManager),
            _addressLine("tokenActionMainManagerAddress", deployed.tokenActionMainManager)
        );
        return content;
    }

    function _addressLine(string memory key, address value) internal pure returns (string memory) {
        return string.concat(key, "=", vm.toString(value), "\n");
    }
}
