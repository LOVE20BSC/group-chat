// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {DeployGroupChat} from "../script/deploy/DeployGroupChat.s.sol";
import {MockLOVE20Group} from "./mocks/MockLOVE20Group.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {MockPhase} from "./mocks/MockPhase.sol";
import {TestBase} from "./utils/TestBase.sol";

contract DeployGroupChatHarness is DeployGroupChat {
    function deployForTest(Dependencies memory deps, DeployConfig memory config)
        external
        returns (DeployedAddresses memory deployed)
    {
        _validateConfig(deps, config);
        _deployCore(deps, config, deployed);
        _deployManagers(deps, config, deployed);
        _validateDeployment(deps, config, deployed);
    }

    function validateDependenciesForTest(Dependencies memory deps, CoreAddresses memory core) external view {
        _validateDependencies(deps, core);
    }
}

contract DeployGroupChatTest is TestBase {
    function testT170_deployScriptBuildsAndValidatesGraph() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        DeployGroupChat.DeployedAddresses memory deployed =
            harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), _config());

        assertTrue(deployed.groupChat != address(0));
        assertTrue(deployed.groupChatBanList != address(0));
        assertTrue(deployed.groupMember != address(0));
        assertTrue(deployed.tokenActionMainManager != address(0));
    }

    function testT171_deployScriptRejectsZeroMaxContentLength() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        DeployGroupChat.DeployConfig memory config = _config();
        config.maxContentLength = 0;

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "GROUP_CHAT_MAX_CONTENT_LENGTH must be > 0"));
        harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), config);
    }

    function testT172_deployScriptValidatesDependencyBindings() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        new DeployGroupChatHarness()
            .validateDependenciesForTest(
                _deps(memberNFT, phase, actionTarget, groupActionExecutor), _core(memberNFT, actionTarget)
            );
    }

    function testT173_deployScriptRejectsDerivedAddressMismatch() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        MockLOVE20Protocols otherSubmit = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChat.CoreAddresses memory core = _core(memberNFT, actionTarget);
        core.submit = address(otherSubmit);

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "ActionTarget.submitAddress mismatch"));
        harness.validateDependenciesForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), core);
    }

    function testT174_deployScriptRejectsNameSpaceBelowMinimum() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        memberNFT.setMaxGroupNameLength(10);
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "MemberNFT MAX_NAME_LENGTH must be >= 11"));
        harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), _config());
    }

    function testT175_deployScriptRejectsBanThresholdAbovePrecision() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        DeployGroupChat.DeployConfig memory config = _config();
        config.banThresholdRatio = 1e18 + 1;

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "GROUP_CHAT_BAN_THRESHOLD_RATIO must be <= 1e18"));
        harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), config);
    }

    function testT176_deployScriptRejectsZeroMinSupportMultiplier() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        DeployGroupChat.DeployConfig memory config = _config();
        config.minSupportToOpposeMultiplier = 0;

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert(
            abi.encodeWithSignature("Error(string)", "GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER must be > 0")
        );
        harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), config);
    }

    function testT177_deployScriptRejectsZeroRecentRounds() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        DeployGroupChat.DeployConfig memory config = _config();
        config.actionRecentRounds = 0;

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "GROUP_CHAT_ACTION_RECENT_ROUNDS must be > 0"));
        harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), config);
    }

    function testT179_deployScriptRejectsChainMismatch() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChat.DeployConfig memory config = _config();
        config.chainId = block.chainid + 1;
        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert("Chain ID mismatch");
        harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), config);
    }

    function testT178_deployScriptRejectsNonContractPlugin() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        DeployGroupChat.DeployConfig memory config = _config();
        config.beforePostPlugin = address(0x1234);

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "beforePostPlugin must be a contract"));
        harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), config);
    }

    function _deps(
        MockLOVE20Group memberNFT,
        MockPhase phase,
        MockLOVE20Protocols actionTarget,
        MockLOVE20Protocols groupActionExecutor
    ) internal pure returns (DeployGroupChat.Dependencies memory) {
        return DeployGroupChat.Dependencies({
            groupNft: address(memberNFT),
            phase: address(phase),
            actionTarget: address(actionTarget),
            groupActionExecutor: address(groupActionExecutor)
        });
    }

    function _config() internal view returns (DeployGroupChat.DeployConfig memory) {
        return DeployGroupChat.DeployConfig({
            chainId: block.chainid,
            beforePostPlugin: address(0),
            afterPostPlugin: address(0),
            maxContentLength: 4096,
            maxMentionedSenderIds: 32,
            actionRecentRounds: 3,
            maxAdminIds: 20,
            minSupportToOpposeMultiplier: 10,
            banThresholdRatio: 3e15
        });
    }

    function _core(MockLOVE20Group memberNFT, MockLOVE20Protocols actionTarget)
        internal
        view
        returns (DeployGroupChat.CoreAddresses memory)
    {
        return DeployGroupChat.CoreAddresses({
            love20: memberNFT.LOVE20_TOKEN_ADDRESS(),
            submit: address(actionTarget),
            vote: address(actionTarget),
            stake: address(actionTarget),
            launch: address(actionTarget)
        });
    }
}
