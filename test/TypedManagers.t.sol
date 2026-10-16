// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IBaseManager} from "../src/interfaces/managers/IBaseManager.sol";

import {TokenActionGovManager} from "../src/managers/TokenActionGovManager.sol";
import {TokenActionMainManager} from "../src/managers/TokenActionMainManager.sol";
import {TokenGovManager} from "../src/managers/TokenGovManager.sol";
import {TokenMainManager} from "../src/managers/TokenMainManager.sol";

import {MockERC20Payment} from "./mocks/MockLOVE20Group.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract TypedManagersTest is GroupChatFixture {
    bytes32 internal constant TOKEN_ACTIVATE_SIG = keccak256("Activate(address,uint256,address)");
    bytes32 internal constant TOKEN_ACTION_ACTIVATE_SIG = keccak256("Activate(address,uint256,uint256,address)");

    function testT110_tokenMainManagerStoresTokenAndCombinesEligibility() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        groupId = _activateToken(manager, token);

        assertEq(manager.tokenOfGroup(groupId), token);
        assertEq(manager.groupIdOfToken(token), groupId);
        assertEq(manager.tokensCount(), 1);
        (address[] memory tokens, uint256[] memory tokenGroupIds) = manager.tokens(0, 10, false);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token);
        assertEq(tokenGroupIds.length, 1);
        assertEq(tokenGroupIds[0], groupId);
        _assertStartsWith(groupNft.groupNameOf(groupId), "mgr_token_main_LOVE20_");

        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setBalance(senderOwner, 1);
        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setBalance(senderOwner, 2);
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setBalance(senderOwner, 0);
        protocol.setGovVotes(token, senderOwner, 9);
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));
        assertEq(manager.voteWeightOf(groupId, senderOwner), 9);
        assertEq(manager.totalVoteWeight(groupId), 9);
        protocol.setGovVotes(token, senderOwner, 0);
        protocol.setJoinedAmountByAccount(token, senderOwner, 1);
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setJoinedAmountByAccount(token, senderOwner, 0);
        protocol.setVotedAction(token, 20, 101, address(protocol));
        protocol.setExtensionJoined(token, 101, senderOwner, true);
        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));

        vm.expectRevert(IBaseManager.AlreadyManaged.selector);
        manager.activate(token);
    }

    function testT111_tokenGovManagerStoresParamsAndUsesGovVoteWeight() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        TokenGovManager manager =
            new TokenGovManager(address(chat), address(0), address(0), address(0), address(protocol));
        vm.recordLogs();
        groupId = manager.activate(token);
        _assertTokenActivate(vm.getRecordedLogs(), address(manager), token, groupId, address(this));

        assertEq(manager.tokenOfGroup(groupId), token);
        assertEq(manager.groupIdOfToken(token), groupId);
        assertEq(manager.tokensCount(), 1);
        (address[] memory tokens, uint256[] memory tokenGroupIds) = manager.tokens(0, 10, false);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token);
        assertEq(tokenGroupIds.length, 1);
        assertEq(tokenGroupIds[0], groupId);
        _assertStartsWith(groupNft.groupNameOf(groupId), "mgr_token_gov_LOVE20_");

        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setGovVotes(token, senderOwner, 7);
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));
        assertEq(manager.voteWeightOf(groupId, senderOwner), 7);
        assertEq(manager.totalVoteWeight(groupId), 7);
    }

    function testT112_tokenActionGovManagerStoresParamsAndUsesRecentVotes() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        TokenActionGovManager manager =
            new TokenActionGovManager(address(chat), address(0), address(0), address(0), address(protocol), 3);

        vm.expectRevert(IBaseManager.RecentRoundsZero.selector);
        new TokenActionGovManager(address(chat), address(0), address(0), address(0), address(protocol), 0);

        vm.expectRevert(IBaseManager.ActionIdNotExist.selector);
        manager.activate(token, 42);

        protocol.setActionsCount(token, 44);
        protocol.setCurrentRound(7);
        vm.recordLogs();
        groupId = manager.activate(token, 42);
        _assertTokenActionActivate(vm.getRecordedLogs(), address(manager), token, 42, groupId, address(this));
        (address storedToken, uint256 actionId) = manager.actionOfGroup(groupId);
        assertEq(storedToken, token);
        assertEq(actionId, 42);
        assertEq(manager.RECENT_ROUNDS(), 3);
        assertEq(manager.groupIdOfAction(token, 42), groupId);
        assertEq(manager.actionsByTokenCount(token), 1);
        (uint256[] memory actionIds, uint256[] memory actionGroupIds) = manager.actionsByToken(token, 0, 10, false);
        assertEq(actionIds.length, 1);
        assertEq(actionIds[0], 42);
        assertEq(actionGroupIds.length, 1);
        assertEq(actionGroupIds[0], groupId);
        _assertStartsWith(groupNft.groupNameOf(groupId), "mgr_action_gov_LOVE20_42_");

        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setActionVotes(token, 5, senderOwner, 42, 1);
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setActionVotes(token, 7, senderOwner, 42, 5);
        protocol.setGovVotes(token, senderOwner, 5);
        assertEq(manager.voteWeightOf(groupId, senderOwner), 5);
        assertEq(manager.totalVoteWeight(groupId), 5);

        uint256 secondGroupId = manager.activate(token, 43);
        uint256[] memory queryActionIds = new uint256[](3);
        queryActionIds[0] = 43;
        queryActionIds[1] = 44;
        queryActionIds[2] = 42;
        uint256[] memory groupIds = manager.groupIdsOfActions(token, queryActionIds);
        assertEq(groupIds.length, 3);
        assertEq(groupIds[0], secondGroupId);
        assertEq(groupIds[1], 0);
        assertEq(groupIds[2], groupId);
        (address[] memory actionTokens, uint256[] memory actionIdsOfGroups) = manager.actionsOfGroups(groupIds);
        assertEq(actionTokens.length, 3);
        assertEq(actionTokens[0], token);
        assertEq(actionTokens[1], address(0));
        assertEq(actionTokens[2], token);
        assertEq(actionIdsOfGroups.length, 3);
        assertEq(actionIdsOfGroups[0], 43);
        assertEq(actionIdsOfGroups[1], 0);
        assertEq(actionIdsOfGroups[2], 42);

        (actionIds, actionGroupIds) = manager.actionsByToken(token, 0, 1, true);
        assertEq(actionIds.length, 1);
        assertEq(actionIds[0], 43);
        assertEq(actionGroupIds.length, 1);
        assertEq(actionGroupIds[0], secondGroupId);
    }

    function testT113_tokenActionMainManagerStoresParamsAndAllowsVoteOrParticipation() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        TokenActionMainManager manager =
            new TokenActionMainManager(address(chat), address(0), address(0), address(0), address(protocol), 3);
        protocol.setActionsCount(token, 90);
        protocol.setCurrentRound(10);
        groupId = manager.activate(token, 88);

        (address storedToken, uint256 actionId) = manager.actionOfGroup(groupId);
        assertEq(storedToken, token);
        assertEq(actionId, 88);
        assertEq(manager.RECENT_ROUNDS(), 3);
        assertEq(manager.groupIdOfAction(token, 88), groupId);
        assertEq(manager.actionsByTokenCount(token), 1);
        (uint256[] memory actionIds, uint256[] memory actionGroupIds) = manager.actionsByToken(token, 0, 10, false);
        assertEq(actionIds.length, 1);
        assertEq(actionIds[0], 88);
        assertEq(actionGroupIds.length, 1);
        assertEq(actionGroupIds[0], groupId);
        _assertStartsWith(groupNft.groupNameOf(groupId), "mgr_action_main_LOVE20_88_");

        assertTrue(!_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setActionVotes(token, 9, senderOwner, 88, 1);
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setActionVotes(token, 9, senderOwner, 88, 0);
        protocol.setJoinedAmount(token, 88, senderOwner, 1);
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setJoinedAmount(token, 88, senderOwner, 0);
        protocol.setExtensionJoined(token, 88, senderOwner, true);
        assertTrue(_canPostAllowed(groupId, senderId, senderOwner));
        protocol.setActionVotes(token, 10, senderOwner, 88, 11);
        protocol.setGovVotes(token, senderOwner, 11);
        assertEq(manager.voteWeightOf(groupId, senderOwner), 11);
        assertEq(manager.totalVoteWeight(groupId), 11);

        uint256 secondGroupId = manager.activate(token, 89);
        uint256[] memory queryActionIds = new uint256[](3);
        queryActionIds[0] = 89;
        queryActionIds[1] = 90;
        queryActionIds[2] = 88;
        uint256[] memory groupIds = manager.groupIdsOfActions(token, queryActionIds);
        assertEq(groupIds.length, 3);
        assertEq(groupIds[0], secondGroupId);
        assertEq(groupIds[1], 0);
        assertEq(groupIds[2], groupId);
        (address[] memory actionTokens, uint256[] memory actionIdsOfGroups) = manager.actionsOfGroups(groupIds);
        assertEq(actionTokens.length, 3);
        assertEq(actionTokens[0], token);
        assertEq(actionTokens[1], address(0));
        assertEq(actionTokens[2], token);
        assertEq(actionIdsOfGroups.length, 3);
        assertEq(actionIdsOfGroups[0], 89);
        assertEq(actionIdsOfGroups[1], 0);
        assertEq(actionIdsOfGroups[2], 88);

        (actionIds, actionGroupIds) = manager.actionsByToken(token, 0, 1, true);
        assertEq(actionIds.length, 1);
        assertEq(actionIds[0], 89);
        assertEq(actionGroupIds.length, 1);
        assertEq(actionGroupIds[0], secondGroupId);
    }

    function testT113B_tokenActionManagersAcceptZeroActionId() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        protocol.setActionsCount(token, 1);
        protocol.setCurrentRound(3);

        TokenActionGovManager govManager =
            new TokenActionGovManager(address(chat), address(0), address(0), address(0), address(protocol), 3);
        uint256 govGroupId = govManager.activate(token, 0);

        (address govToken, uint256 govActionId) = govManager.actionOfGroup(govGroupId);
        assertEq(govToken, token);
        assertEq(govActionId, 0);
        assertEq(govManager.groupIdOfAction(token, 0), govGroupId);

        uint256[] memory queryActionIds = new uint256[](1);
        queryActionIds[0] = 0;
        uint256[] memory groupIds = govManager.groupIdsOfActions(token, queryActionIds);
        assertEq(groupIds.length, 1);
        assertEq(groupIds[0], govGroupId);

        (uint256[] memory actionIds, uint256[] memory actionGroupIds) = govManager.actionsByToken(token, 0, 10, false);
        assertEq(actionIds.length, 1);
        assertEq(actionIds[0], 0);
        assertEq(actionGroupIds.length, 1);
        assertEq(actionGroupIds[0], govGroupId);

        protocol.setActionVotes(token, 3, senderOwner, 0, 1);
        assertTrue(_canPostAllowed(govGroupId, senderId, senderOwner));

        TokenActionMainManager mainManager =
            new TokenActionMainManager(address(chat), address(0), address(0), address(0), address(protocol), 3);
        uint256 mainGroupId = mainManager.activate(token, 0);

        (address mainToken, uint256 mainActionId) = mainManager.actionOfGroup(mainGroupId);
        assertEq(mainToken, token);
        assertEq(mainActionId, 0);
        assertEq(mainManager.groupIdOfAction(token, 0), mainGroupId);
        assertTrue(_canPostAllowed(mainGroupId, senderId, senderOwner));
    }

    function testT116_tokenMainManagersPageTokens() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockLOVE20Protocols secondProtocol = new MockLOVE20Protocols();
        address token = address(protocol);
        address secondToken = address(secondProtocol);

        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        manager.activate(token);
        uint256 secondGroupId = manager.activate(secondToken);

        assertEq(manager.tokensCount(), 2);
        (address[] memory tokens, uint256[] memory tokenGroupIds) = manager.tokens(0, 10, false);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token);
        assertEq(tokens[1], secondToken);
        assertEq(tokenGroupIds.length, 2);
        assertEq(tokenGroupIds[0], manager.groupIdOfToken(token));
        assertEq(tokenGroupIds[1], secondGroupId);

        (tokens, tokenGroupIds) = manager.tokens(0, 1, true);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], secondToken);
        assertEq(tokenGroupIds.length, 1);
        assertEq(tokenGroupIds[0], secondGroupId);

        (tokens, tokenGroupIds) = manager.tokens(2, 10, false);
        assertEq(tokens.length, 0);
        assertEq(tokenGroupIds.length, 0);

        TokenGovManager govManager =
            new TokenGovManager(address(chat), address(0), address(0), address(0), address(protocol));
        govManager.activate(token);
        secondGroupId = govManager.activate(secondToken);

        assertEq(govManager.tokensCount(), 2);
        (tokens, tokenGroupIds) = govManager.tokens(1, 10, false);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], secondToken);
        assertEq(tokenGroupIds.length, 1);
        assertEq(tokenGroupIds[0], secondGroupId);
    }

    function testT114_typedManagerProtocolDependenciesRequireCode() public {
        vm.expectRevert(IBaseManager.ManagerAddressHasNoCode.selector);
        new TokenGovManager(address(chat), address(0), address(0), address(0), other);

        vm.expectRevert(IBaseManager.ManagerAddressHasNoCode.selector);
        new TokenMainManager(address(chat), address(0), address(0), address(0), other);

        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        protocol.setLOVE20Token(token, false);
        TokenGovManager manager =
            new TokenGovManager(address(chat), address(0), address(0), address(0), address(protocol));

        vm.expectRevert(IBaseManager.TokenNotLOVE20.selector);
        manager.activate(token);
    }

    function testT115_tokenMainManagerMintSurvivesTestPrefixNormalization() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment payment = new MockERC20Payment();
        payment.setSymbol("TestLOVE");
        groupNft.setMintPayment(address(payment), 10);
        payment.mint(address(this), 10);

        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        payment.approve(address(manager), 10);

        groupId = manager.activate(address(protocol));

        assertEq(chat.chatInfo(groupId).owner, address(manager));
        _assertStartsWith(groupNft.groupNameOf(groupId), "Testmgr_token_main_LOVE20_");
    }

    function _activateToken(TokenMainManager manager, address token) internal returns (uint256) {
        return manager.activate(token);
    }

    function _assertStartsWith(string memory value, string memory prefix) internal pure {
        bytes memory valueBytes = bytes(value);
        bytes memory prefixBytes = bytes(prefix);
        assertTrue(valueBytes.length >= prefixBytes.length);
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            assertEq(valueBytes[i], prefixBytes[i]);
        }
    }

    function _assertTokenActivate(
        Vm.Log[] memory logs,
        address manager,
        address token,
        uint256 activatedGroupId,
        address operator
    ) internal pure {
        Vm.Log memory log = logs[logs.length - 1];
        assertEq(log.emitter, manager);
        assertEq(log.topics[0], TOKEN_ACTIVATE_SIG);
        assertEq(log.topics[1], _topicAddress(token));
        assertEq(log.topics[2], bytes32(activatedGroupId));
        assertEq(log.topics[3], _topicAddress(operator));
        assertEq(log.data.length, 0);
    }

    function _assertTokenActionActivate(
        Vm.Log[] memory logs,
        address manager,
        address token,
        uint256 actionId,
        uint256 activatedGroupId,
        address operator
    ) internal pure {
        Vm.Log memory log = logs[logs.length - 1];
        assertEq(log.emitter, manager);
        assertEq(log.topics[0], TOKEN_ACTION_ACTIVATE_SIG);
        assertEq(log.topics[1], _topicAddress(token));
        assertEq(log.topics[2], bytes32(actionId));
        assertEq(log.topics[3], bytes32(activatedGroupId));
        assertEq(abi.decode(log.data, (address)), operator);
    }

    function _topicAddress(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}
