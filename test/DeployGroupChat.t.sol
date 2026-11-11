// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {DeployGroupChat} from "../script/deploy/DeployGroupChat.s.sol";
import {IManagerBase} from "../src/interfaces/managers/IManagerBase.sol";
import {ITokenScopeManagerBase} from "../src/interfaces/managers/ITokenScopeManagerBase.sol";
import {MockERC20Payment, MockLOVE20Group} from "./mocks/MockLOVE20Group.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {MockPhase} from "./mocks/MockPhase.sol";
import {MockAfterPostCapturePlugin, MockBeforePostCapturePlugin} from "./mocks/MockPlugins.sol";
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

    function longestTypeCodeBytesForTest() external pure returns (uint256) {
        return LONGEST_MANAGER_TYPE_CODE_BYTES;
    }

    function nameReservedBytesForTest() external pure returns (uint256) {
        return GROUP_NAME_SEPARATOR_BYTES + GROUP_NAME_RANDOM_HEX_LENGTH;
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

    // T171 is intentionally unused: test IDs are stable labels, never reused or renumbered.
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
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "ActionTarget.SUBMIT_ADDRESS mismatch"));
        harness.validateDependenciesForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), core);
    }

    function testT174_deployScriptRejectsNameSpaceBelowPreBroadcastBound() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        uint256 minNameLength = harness.longestTypeCodeBytesForTest() + harness.nameReservedBytesForTest();
        memberNFT.setMaxGroupNameLength(minNameLength - 1);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)", string.concat("MemberNFT MAX_NAME_LENGTH must be >= ", vm.toString(minNameLength))
            )
        );
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

    function testT181_deployScriptNameSpaceBoundMatchesTypeCodes() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        DeployGroupChat.DeployedAddresses memory deployed =
            harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), _config());

        address[4] memory managers = [
            deployed.tokenMainManager,
            deployed.tokenGovManager,
            deployed.tokenActionGovManager,
            deployed.tokenActionMainManager
        ];
        uint256 longestTypeCode;
        for (uint256 i = 0; i < managers.length; i++) {
            uint256 typeCodeLength = bytes(IManagerBase(managers[i]).TYPE_CODE()).length;
            if (typeCodeLength > longestTypeCode) {
                longestTypeCode = typeCodeLength;
            }
        }
        assertEq(harness.longestTypeCodeBytesForTest(), longestTypeCode);

        memberNFT.setMaxGroupNameLength(harness.longestTypeCodeBytesForTest() + harness.nameReservedBytesForTest());
        DeployGroupChat.DeployedAddresses memory redeployed =
            harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), _config());
        assertTrue(redeployed.tokenActionGovManager != address(0));
    }

    function testT182_deployScriptRejectsZeroMaxAdminIds() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        DeployGroupChat.DeployConfig memory config = _config();
        config.maxAdminIds = 0;

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "GROUP_CHAT_MAX_ADMIN_IDS must be > 0"));
        harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), config);
    }

    function testT183_deployScriptRejectsNonContractAfterPostPlugin() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        DeployGroupChat.DeployConfig memory config = _config();
        config.afterPostPlugin = address(0x1234);

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "afterPostPlugin must be a contract"));
        harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), config);
    }

    function testT184_deployScriptRejectsZeroOriginPhaseBlocks() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 0);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        DeployGroupChat.CoreAddresses memory core = _core(memberNFT, actionTarget);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Phase.ORIGIN_PHASE_BLOCKS must be > 0"));
        harness.validateDependenciesForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), core);
    }

    function testT185_deployScriptRejectsNonContractDependencies() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChat.CoreAddresses memory core = _core(memberNFT, actionTarget);
        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        address noCode = address(0xDEAD);

        DeployGroupChat.Dependencies memory deps = _deps(memberNFT, phase, actionTarget, groupActionExecutor);
        deps.groupNft = noCode;
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "MemberNFT must be a deployed contract"));
        harness.validateDependenciesForTest(deps, core);

        deps = _deps(memberNFT, phase, actionTarget, groupActionExecutor);
        deps.phase = noCode;
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Phase must be a deployed contract"));
        harness.validateDependenciesForTest(deps, core);

        deps = _deps(memberNFT, phase, actionTarget, groupActionExecutor);
        deps.actionTarget = noCode;
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "ActionTarget must be a deployed contract"));
        harness.validateDependenciesForTest(deps, core);

        deps = _deps(memberNFT, phase, actionTarget, groupActionExecutor);
        deps.groupActionExecutor = noCode;
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "GroupActionExecutor must be a deployed contract"));
        harness.validateDependenciesForTest(deps, core);
    }

    function testT186_deployScriptRejectsActionTargetRootBindings() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        DeployGroupChat.Dependencies memory deps = _deps(memberNFT, phase, actionTarget, groupActionExecutor);

        actionTarget.setMemberNFTAddress(address(0x1234));
        DeployGroupChat.CoreAddresses memory core = _core(memberNFT, actionTarget);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "ActionTarget.MEMBER_NFT_ADDRESS mismatch"));
        harness.validateDependenciesForTest(deps, core);

        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(0x1234));
        core = _core(memberNFT, actionTarget);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "ActionTarget.PHASE_ADDRESS mismatch"));
        harness.validateDependenciesForTest(deps, core);
    }

    function testT187_deployScriptRejectsRootTokenMismatch() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        DeployGroupChat.Dependencies memory deps = _deps(memberNFT, phase, actionTarget, groupActionExecutor);

        memberNFT.setMintPayment(address(0xDEAD), 0);
        DeployGroupChat.CoreAddresses memory core = _core(memberNFT, actionTarget);
        vm.expectRevert(
            abi.encodeWithSignature("Error(string)", "MemberNFT.LOVE20_TOKEN_ADDRESS must be a contract")
        );
        harness.validateDependenciesForTest(deps, core);

        memberNFT.setMintPayment(address(actionTarget), 0);
        core = _core(memberNFT, actionTarget);
        core.love20 = address(groupActionExecutor);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "MemberNFT root token mismatch"));
        harness.validateDependenciesForTest(deps, core);
    }

    function testT188_deployScriptRejectsDerivedAddressMismatch() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        MockLOVE20Protocols otherCore = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        DeployGroupChat.Dependencies memory deps = _deps(memberNFT, phase, actionTarget, groupActionExecutor);

        DeployGroupChat.CoreAddresses memory core = _core(memberNFT, actionTarget);
        core.vote = address(otherCore);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "ActionTarget.VOTE_ADDRESS mismatch"));
        harness.validateDependenciesForTest(deps, core);

        core = _core(memberNFT, actionTarget);
        core.stake = address(otherCore);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Vote.STAKE_ADDRESS mismatch"));
        harness.validateDependenciesForTest(deps, core);

        core = _core(memberNFT, actionTarget);
        core.launch = address(otherCore);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Stake.LAUNCH_ADDRESS mismatch"));
        harness.validateDependenciesForTest(deps, core);
    }

    function testT189_deployScriptRejectsNonContractDerivedDependencies() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        DeployGroupChat.Dependencies memory deps = _deps(memberNFT, phase, actionTarget, groupActionExecutor);
        DeployGroupChat.CoreAddresses memory core = _core(memberNFT, actionTarget);
        address noCode = address(0xDEAD);

        actionTarget.setSubmitAddress(noCode);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "ActionTarget.SUBMIT_ADDRESS must be a contract"));
        harness.validateDependenciesForTest(deps, core);

        actionTarget.setSubmitAddress(address(actionTarget));
        actionTarget.setVoteAddress(noCode);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "ActionTarget.VOTE_ADDRESS must be a contract"));
        harness.validateDependenciesForTest(deps, core);

        actionTarget.setVoteAddress(address(actionTarget));
        actionTarget.setStakeAddress(noCode);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Vote.STAKE_ADDRESS must be a contract"));
        harness.validateDependenciesForTest(deps, core);

        actionTarget.setStakeAddress(address(actionTarget));
        actionTarget.setLaunchAddress(noCode);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Stake.LAUNCH_ADDRESS must be a contract"));
        harness.validateDependenciesForTest(deps, core);
    }

    function testT190_deployScriptRejectsStakePhaseMismatch() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        MockLOVE20Protocols stakeDouble = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        stakeDouble.setPhaseAddress(address(0x1234));
        actionTarget.setStakeAddress(address(stakeDouble));

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        DeployGroupChat.Dependencies memory deps = _deps(memberNFT, phase, actionTarget, groupActionExecutor);
        DeployGroupChat.CoreAddresses memory core = _core(memberNFT, actionTarget);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Stake.PHASE_ADDRESS mismatch"));
        harness.validateDependenciesForTest(deps, core);
    }

    function testT191_deployScriptWiresPluginSlotsIntoEveryManager() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        MockBeforePostCapturePlugin beforePlugin = new MockBeforePostCapturePlugin();
        MockAfterPostCapturePlugin afterPlugin = new MockAfterPostCapturePlugin();

        DeployGroupChat.DeployConfig memory config = _config();
        config.beforePostPlugin = address(beforePlugin);
        config.afterPostPlugin = address(afterPlugin);

        DeployGroupChat.DeployedAddresses memory deployed =
            new DeployGroupChatHarness().deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), config);

        address[4] memory managers = [
            deployed.tokenMainManager,
            deployed.tokenGovManager,
            deployed.tokenActionGovManager,
            deployed.tokenActionMainManager
        ];
        for (uint256 i = 0; i < managers.length; i++) {
            assertEq(IManagerBase(managers[i]).BEFORE_POST_PLUGIN_ADDRESS(), address(beforePlugin));
            assertEq(IManagerBase(managers[i]).AFTER_POST_PLUGIN_ADDRESS(), address(afterPlugin));
            assertEq(IManagerBase(managers[i]).BAN_SOURCE_ADDRESS(), deployed.govVotedBanSource);
            assertEq(IManagerBase(managers[i]).GROUP_CHAT_ADDRESS(), deployed.groupChat);
        }
    }

    function testT192_managerNameBudgetMatchesDeployScriptFloor() public {
        MockLOVE20Group memberNFT = new MockLOVE20Group();
        MockPhase phase = new MockPhase(block.number + 50, 100);
        MockLOVE20Protocols actionTarget = new MockLOVE20Protocols();
        MockLOVE20Protocols groupActionExecutor = new MockLOVE20Protocols();
        actionTarget.setMemberNFTAddress(address(memberNFT));
        actionTarget.setPhaseAddress(address(phase));

        DeployGroupChatHarness harness = new DeployGroupChatHarness();
        uint256 scriptFloor = harness.longestTypeCodeBytesForTest() + harness.nameReservedBytesForTest();
        memberNFT.setMaxGroupNameLength(scriptFloor);

        DeployGroupChat.DeployedAddresses memory deployed =
            harness.deployForTest(_deps(memberNFT, phase, actionTarget, groupActionExecutor), _config());

        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol("AAA");
        uint256 groupId = ITokenScopeManagerBase(deployed.tokenMainManager).activate(address(token));

        string memory name = memberNFT.groupNameOf(groupId);
        assertEq(bytes(name).length, scriptFloor);
        _assertPrefix(name, "tm_");
        bytes memory nameBytes = bytes(name);
        for (uint256 i = 3; i < nameBytes.length; i++) {
            bytes1 char = nameBytes[i];
            assertTrue((char >= "0" && char <= "9") || (char >= "a" && char <= "f"));
        }
    }

    function _assertPrefix(string memory haystack, string memory prefix) internal pure {
        bytes memory subject = bytes(haystack);
        bytes memory expected = bytes(prefix);
        assertTrue(subject.length >= expected.length);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(uint256(uint8(subject[i])), uint256(uint8(expected[i])));
        }
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
