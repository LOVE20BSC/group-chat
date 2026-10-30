// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IManagerBase, IManagerBaseErrors} from "../src/interfaces/managers/IManagerBase.sol";
import {ITokenActionScopeManagerBaseErrors} from "../src/interfaces/managers/ITokenActionScopeManagerBase.sol";

import {TokenActionGovManager} from "../src/managers/TokenActionGovManager.sol";
import {TokenActionMainManager} from "../src/managers/TokenActionMainManager.sol";
import {TokenGovManager} from "../src/managers/TokenGovManager.sol";
import {TokenMainManager} from "../src/managers/TokenMainManager.sol";

import {MockERC20Payment} from "./mocks/MockLOVE20Group.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";
import {Vm} from "./utils/TestBase.sol";

contract TypedManagersTest is GroupChatFixture {
    bytes32 internal constant TOKEN_GROUP_ACTIVATED_SIG = keccak256("TokenGroupActivated(address,uint256,address)");
    bytes32 internal constant TOKEN_ACTION_GROUP_ACTIVATED_SIG =
        keccak256("TokenActionGroupActivated(address,uint256,uint256,address)");

    function testT110_tokenMainManagerStoresTokenAndCombinesEligibility() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        groupId = _activateToken(manager, token);

        assertEq(manager.tokenAddressByGroupId(groupId), token);
        assertEq(manager.groupIdByTokenAddress(token), groupId);
        assertEq(tokensTotal(manager), 1);
        (address[] memory tokens, uint256[] memory tokenGroupIds, ) = manager.tokens(0, 10, false);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token);
        assertEq(tokenGroupIds.length, 1);
        assertEq(tokenGroupIds[0], groupId);
        _assertStartsWith(groupNft.groupNameOf(groupId), "tm_TestLOVE20_");

        assertTrue(!_canPostAllowed(groupId, senderId));
        protocol.setBalance(senderOwner, 1);
        assertTrue(_canPostAllowed(groupId, senderId));
        protocol.setBalance(senderOwner, 2);
        assertTrue(_canPostAllowed(groupId, senderId));
        protocol.setBalance(senderOwner, 0);
        protocol.setGovVotes(token, senderId, 9);
        assertTrue(_canPostAllowed(groupId, senderId));
        assertEq(manager.voteWeight(groupId, senderId), 9);
        assertEq(manager.totalVoteWeight(groupId), 9);
        protocol.setGovVotes(token, senderId, 0);
        protocol.setActionJoined(token, 1, senderId, true);
        assertTrue(_canPostAllowed(groupId, senderId));
        protocol.clearActionJoined(token, senderId);
        assertTrue(!_canPostAllowed(groupId, senderId));

        vm.expectRevert(abi.encodeWithSelector(IManagerBaseErrors.AlreadyManaged.selector, groupId));
        manager.activate(token);
    }

    function testT111_tokenGovManagerStoresParamsAndUsesGovVoteWeight() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        TokenGovManager manager =
            new TokenGovManager(address(chat), address(0), address(0), address(0), address(protocol));
        vm.recordLogs();
        groupId = manager.activate(token);
        _assertTokenGroupActivated(vm.getRecordedLogs(), address(manager), token, groupId, address(this));

        assertEq(manager.tokenAddressByGroupId(groupId), token);
        assertEq(manager.groupIdByTokenAddress(token), groupId);
        assertEq(tokensTotal(manager), 1);
        (address[] memory tokens, uint256[] memory tokenGroupIds, ) = manager.tokens(0, 10, false);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token);
        assertEq(tokenGroupIds.length, 1);
        assertEq(tokenGroupIds[0], groupId);
        _assertStartsWith(groupNft.groupNameOf(groupId), "tg_TestLOVE20_");

        assertTrue(!_canPostAllowed(groupId, senderId));
        protocol.setGovVotes(token, senderId, 7);
        assertTrue(_canPostAllowed(groupId, senderId));
        assertEq(manager.voteWeight(groupId, senderId), 7);
        assertEq(manager.totalVoteWeight(groupId), 7);
    }

    function testT112_tokenActionGovManagerStoresParamsAndUsesRecentVotes() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        TokenActionGovManager manager =
            new TokenActionGovManager(address(chat), address(0), address(0), address(0), address(protocol), 3);

        vm.expectRevert(
            abi.encodeWithSelector(ITokenActionScopeManagerBaseErrors.ActionNotExist.selector, token, uint256(42))
        );
        manager.activate(token, 42);

        protocol.setActionsCount(token, 44);
        protocol.setCurrentRound(7);
        vm.recordLogs();
        groupId = manager.activate(token, 42);
        _assertTokenActionGroupActivated(vm.getRecordedLogs(), address(manager), token, 42, groupId, address(this));
        (address storedToken, uint256 actionId) = manager.actionByGroupId(groupId);
        assertEq(storedToken, token);
        assertEq(actionId, 42);
        assertEq(manager.RECENT_ROUNDS(), 3);
        assertEq(manager.groupIdByActionId(token, 42), groupId);
        assertEq(actionsTotal(manager, token), 1);
        (uint256[] memory actionIds, uint256[] memory actionGroupIds, ) = manager.actions(token, 0, 10, false);
        assertEq(actionIds.length, 1);
        assertEq(actionIds[0], 42);
        assertEq(actionGroupIds.length, 1);
        assertEq(actionGroupIds[0], groupId);
        _assertStartsWith(groupNft.groupNameOf(groupId), "ag_TestLOVE20_42_");

        assertTrue(!_canPostAllowed(groupId, senderId));
        protocol.setActionVotes(token, 5, senderId, 42, 1);
        assertTrue(_canPostAllowed(groupId, senderId));
        protocol.setActionVotes(token, 7, senderId, 42, 5);
        protocol.setGovVotes(token, senderId, 5);
        assertEq(manager.voteWeight(groupId, senderId), 5);
        assertEq(manager.totalVoteWeight(groupId), 5);

        uint256 secondGroupId = manager.activate(token, 43);
        uint256[] memory queryActionIds = new uint256[](3);
        queryActionIds[0] = 43;
        queryActionIds[1] = 44;
        queryActionIds[2] = 42;
        uint256[] memory groupIds = manager.groupIdsByActionIds(token, queryActionIds);
        assertEq(groupIds.length, 3);
        assertEq(groupIds[0], secondGroupId);
        assertEq(groupIds[1], 0);
        assertEq(groupIds[2], groupId);
        (address[] memory actionTokens, uint256[] memory actionIdsOfGroups) = manager.actionsByGroupIds(groupIds);
        assertEq(actionTokens.length, 3);
        assertEq(actionTokens[0], token);
        assertEq(actionTokens[1], address(0));
        assertEq(actionTokens[2], token);
        assertEq(actionIdsOfGroups.length, 3);
        assertEq(actionIdsOfGroups[0], 43);
        assertEq(actionIdsOfGroups[1], 0);
        assertEq(actionIdsOfGroups[2], 42);

        (actionIds, actionGroupIds, ) = manager.actions(token, 0, 1, true);
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

        (address storedToken, uint256 actionId) = manager.actionByGroupId(groupId);
        assertEq(storedToken, token);
        assertEq(actionId, 88);
        assertEq(manager.RECENT_ROUNDS(), 3);
        assertEq(manager.groupIdByActionId(token, 88), groupId);
        assertEq(actionsTotal(manager, token), 1);
        (uint256[] memory actionIds, uint256[] memory actionGroupIds, ) = manager.actions(token, 0, 10, false);
        assertEq(actionIds.length, 1);
        assertEq(actionIds[0], 88);
        assertEq(actionGroupIds.length, 1);
        assertEq(actionGroupIds[0], groupId);
        _assertStartsWith(groupNft.groupNameOf(groupId), "am_TestLOVE20_88_");

        assertTrue(!_canPostAllowed(groupId, senderId));
        protocol.setActionVotes(token, 9, senderId, 88, 1);
        assertTrue(_canPostAllowed(groupId, senderId));
        protocol.setActionVotes(token, 9, senderId, 88, 0);
        protocol.setActionJoined(token, 88, senderId, true);
        assertTrue(_canPostAllowed(groupId, senderId));
        protocol.setActionVotes(token, 10, senderId, 88, 11);
        protocol.setGovVotes(token, senderId, 11);
        assertEq(manager.voteWeight(groupId, senderId), 11);
        assertEq(manager.totalVoteWeight(groupId), 11);

        uint256 secondGroupId = manager.activate(token, 89);
        uint256[] memory queryActionIds = new uint256[](3);
        queryActionIds[0] = 89;
        queryActionIds[1] = 90;
        queryActionIds[2] = 88;
        uint256[] memory groupIds = manager.groupIdsByActionIds(token, queryActionIds);
        assertEq(groupIds.length, 3);
        assertEq(groupIds[0], secondGroupId);
        assertEq(groupIds[1], 0);
        assertEq(groupIds[2], groupId);
        (address[] memory actionTokens, uint256[] memory actionIdsOfGroups) = manager.actionsByGroupIds(groupIds);
        assertEq(actionTokens.length, 3);
        assertEq(actionTokens[0], token);
        assertEq(actionTokens[1], address(0));
        assertEq(actionTokens[2], token);
        assertEq(actionIdsOfGroups.length, 3);
        assertEq(actionIdsOfGroups[0], 89);
        assertEq(actionIdsOfGroups[1], 0);
        assertEq(actionIdsOfGroups[2], 88);

        (actionIds, actionGroupIds, ) = manager.actions(token, 0, 1, true);
        assertEq(actionIds.length, 1);
        assertEq(actionIds[0], 89);
        assertEq(actionGroupIds.length, 1);
        assertEq(actionGroupIds[0], secondGroupId);
    }

    function testT113B_tokenActionManagersRejectZeroActionId() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        protocol.setActionsCount(token, 1);
        protocol.setCurrentRound(3);

        TokenActionGovManager govManager =
            new TokenActionGovManager(address(chat), address(0), address(0), address(0), address(protocol), 3);
        vm.expectRevert(
            abi.encodeWithSelector(ITokenActionScopeManagerBaseErrors.ActionNotExist.selector, token, uint256(0))
        );
        govManager.activate(token, 0);
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

        assertEq(tokensTotal(manager), 2);
        (address[] memory tokens, uint256[] memory tokenGroupIds, ) = manager.tokens(0, 10, false);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token);
        assertEq(tokens[1], secondToken);
        assertEq(tokenGroupIds.length, 2);
        assertEq(tokenGroupIds[0], manager.groupIdByTokenAddress(token));
        assertEq(tokenGroupIds[1], secondGroupId);

        (tokens, tokenGroupIds, ) = manager.tokens(0, 1, true);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], secondToken);
        assertEq(tokenGroupIds.length, 1);
        assertEq(tokenGroupIds[0], secondGroupId);

        (tokens, tokenGroupIds, ) = manager.tokens(2, 10, false);
        assertEq(tokens.length, 0);
        assertEq(tokenGroupIds.length, 0);

        TokenGovManager govManager =
            new TokenGovManager(address(chat), address(0), address(0), address(0), address(protocol));
        govManager.activate(token);
        secondGroupId = govManager.activate(secondToken);

        assertEq(tokensTotal(govManager), 2);
        (tokens, tokenGroupIds, ) = govManager.tokens(1, 10, false);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], secondToken);
        assertEq(tokenGroupIds.length, 1);
        assertEq(tokenGroupIds[0], secondGroupId);
    }

    function testT114_typedManagerRejectsNonLOVE20Token() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address token = address(protocol);
        protocol.setLOVE20Token(token, false);
        TokenGovManager manager =
            new TokenGovManager(address(chat), address(0), address(0), address(0), address(protocol));

        vm.expectRevert(abi.encodeWithSelector(IManagerBaseErrors.TokenNotLOVE20.selector, token));
        manager.activate(token);
    }

    function testT115_tokenMainManagerMintSurvivesTestPrefixNormalization() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment payment = new MockERC20Payment();
        payment.setSymbol("TestLOVE20");
        groupNft.setMintPayment(address(payment), 10);
        payment.mint(address(this), 10);

        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        payment.approve(address(manager), 10);

        groupId = manager.activate(address(protocol));

        assertEq(chat.chatInfo(groupId).owner, address(manager));
        _assertStartsWith(groupNft.groupNameOf(groupId), "Testtm_TestLOVE20_");
    }

    function testT117_tokenMainManagerKeepsChineseSymbol() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol(unicode"测试");

        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        groupId = _activateToken(manager, address(token));

        string memory name = groupNft.groupNameOf(groupId);
        _assertStartsWith(name, unicode"tm_测试_");
        assertEq(bytes(name).length, 14);
    }

    function testT118_tokenMainManagerDropsPayloadWhenSymbolTooLong() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol(_repeatAscii("A", 30));

        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        groupId = manager.activate(address(token));

        string memory name = groupNft.groupNameOf(groupId);
        assertEq(bytes(name).length, 32);
        _assertStartsWith(name, "tm_");
        _assertHexFrom(name, 3);
    }

    function testT119_actionManagerDropsPayloadWhenSymbolTooLong() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol(_repeatAscii("A", 30));
        protocol.setActionsCount(address(token), 42);

        TokenActionMainManager manager =
            new TokenActionMainManager(address(chat), address(0), address(0), address(0), address(protocol), 3);
        groupId = manager.activate(address(token), 42);

        string memory name = groupNft.groupNameOf(groupId);
        assertEq(bytes(name).length, 32);
        _assertStartsWith(name, "am_");
        _assertHexFrom(name, 3);
    }

    function testT120_testPrefixBudgetDropsAtTwentyOneBytes() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment love20Payment = MockERC20Payment(groupNft.LOVE20_TOKEN_ADDRESS());
        love20Payment.setSymbol("TestLOVE20");

        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));

        MockERC20Payment fits = new MockERC20Payment();
        fits.setSymbol(_repeatAscii("A", 20));
        string memory fitsName = groupNft.groupNameOf(manager.activate(address(fits)));
        _assertStartsWith(fitsName, string(abi.encodePacked("Testtm_", _repeatAscii("A", 20), "_")));
        assertEq(bytes(fitsName).length, 32);

        MockERC20Payment overflow = new MockERC20Payment();
        overflow.setSymbol(_repeatAscii("A", 21));
        string memory overflowName = groupNft.groupNameOf(manager.activate(address(overflow)));
        _assertStartsWith(overflowName, "Testtm_");
        assertEq(bytes(overflowName).length, 32);
        _assertHexFrom(overflowName, 7);
    }

    function testT121_tokenMainManagerDropsSymbolWhenNoNameSafeChars() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol("!!!");

        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        groupId = manager.activate(address(token));

        string memory name = groupNft.groupNameOf(groupId);
        assertEq(bytes(name).length, 32);
        _assertStartsWith(name, "tm_");
        _assertHexFrom(name, 3);
    }

    function testT122_actionManagerKeepsSixDigitAction() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol("ABCD");
        protocol.setActionsCount(address(token), 123456);

        TokenActionMainManager manager =
            new TokenActionMainManager(address(chat), address(0), address(0), address(0), address(protocol), 3);
        groupId = manager.activate(address(token), 123456);

        string memory name = groupNft.groupNameOf(groupId);
        _assertStartsWith(name, "am_ABCD_123456_");
        assertEq(bytes(name).length, 19);
    }

    function testT123_actionManagerDropsPayloadWhenSymbolPlusActionTooLong() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol(_repeatAscii("A", 20));
        protocol.setActionsCount(address(token), 123456);

        TokenActionMainManager manager =
            new TokenActionMainManager(address(chat), address(0), address(0), address(0), address(protocol), 3);
        groupId = manager.activate(address(token), 123456);

        string memory name = groupNft.groupNameOf(groupId);
        assertEq(bytes(name).length, 32);
        _assertStartsWith(name, "am_");
        _assertHexFrom(name, 3);
    }

    function testFuzz_T124_tokenMainManagerNameAlwaysFits(uint256 symbolLengthSeed) public {
        uint256 symbolLength = symbolLengthSeed % 80 + 1;
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol(_repeatAscii("A", symbolLength));

        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        groupId = manager.activate(address(token));

        string memory name = groupNft.groupNameOf(groupId);
        bytes memory nameBytes = bytes(name);
        _assertStartsWith(name, "tm_");

        if (symbolLength <= 24) {
            assertEq(nameBytes.length, symbolLength + 8);
            assertTrue(nameBytes[3] == "A");
        } else {
            assertEq(nameBytes.length, 32);
            _assertHexFrom(name, 3);
        }
    }

    function testT125_actionPayloadBoundary() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        TokenActionMainManager manager =
            new TokenActionMainManager(address(chat), address(0), address(0), address(0), address(protocol), 3);

        MockERC20Payment normalFits = new MockERC20Payment();
        normalFits.setSymbol(_repeatAscii("A", 17));
        protocol.setActionsCount(address(normalFits), 123456);
        string memory normalFitsName = groupNft.groupNameOf(manager.activate(address(normalFits), 123456));
        _assertStartsWith(normalFitsName, string(abi.encodePacked("am_", _repeatAscii("A", 17), "_123456_")));
        assertEq(bytes(normalFitsName).length, 32);

        MockERC20Payment normalOverflow = new MockERC20Payment();
        normalOverflow.setSymbol(_repeatAscii("A", 18));
        protocol.setActionsCount(address(normalOverflow), 123456);
        string memory normalOverflowName = groupNft.groupNameOf(manager.activate(address(normalOverflow), 123456));
        assertEq(bytes(normalOverflowName).length, 32);
        _assertStartsWith(normalOverflowName, "am_");
        _assertHexFrom(normalOverflowName, 3);

        MockERC20Payment love20Payment = MockERC20Payment(groupNft.LOVE20_TOKEN_ADDRESS());
        love20Payment.setSymbol("TestLOVE20");

        MockERC20Payment testFits = new MockERC20Payment();
        testFits.setSymbol(_repeatAscii("A", 13));
        protocol.setActionsCount(address(testFits), 123456);
        string memory testFitsName = groupNft.groupNameOf(manager.activate(address(testFits), 123456));
        _assertStartsWith(testFitsName, string(abi.encodePacked("Testam_", _repeatAscii("A", 13), "_123456_")));
        assertEq(bytes(testFitsName).length, 32);

        MockERC20Payment testOverflow = new MockERC20Payment();
        testOverflow.setSymbol(_repeatAscii("A", 14));
        protocol.setActionsCount(address(testOverflow), 123456);
        string memory testOverflowName = groupNft.groupNameOf(manager.activate(address(testOverflow), 123456));
        assertEq(bytes(testOverflowName).length, 32);
        _assertStartsWith(testOverflowName, "Testam_");
        _assertHexFrom(testOverflowName, 7);
    }

    function testT126_actionManagerUsesActionOnlyWhenSymbolIsEmpty() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol("!!!");
        protocol.setActionsCount(address(token), 42);

        TokenActionMainManager manager =
            new TokenActionMainManager(address(chat), address(0), address(0), address(0), address(protocol), 3);
        groupId = manager.activate(address(token), 42);

        string memory name = groupNft.groupNameOf(groupId);
        _assertStartsWith(name, "am_42_");
        assertEq(bytes(name).length, 10);
    }

    function testT127_tokenManagerFitsAtMinimumNameLength() public {
        groupNft.setMaxGroupNameLength(11);
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));

        MockERC20Payment fits = new MockERC20Payment();
        fits.setSymbol("AAA");
        string memory fitsName = groupNft.groupNameOf(manager.activate(address(fits)));
        _assertStartsWith(fitsName, "tm_AAA_");
        assertEq(bytes(fitsName).length, 11);

        MockERC20Payment overflow = new MockERC20Payment();
        overflow.setSymbol("AAAA");
        string memory overflowName = groupNft.groupNameOf(manager.activate(address(overflow)));
        assertEq(bytes(overflowName).length, 11);
        _assertStartsWith(overflowName, "tm_");
        _assertHexFrom(overflowName, 3);
    }

    function testT128_tokenManagerTestPrefixAtMinimumNameLength() public {
        groupNft.setMaxGroupNameLength(11);
        MockERC20Payment love20Payment = MockERC20Payment(groupNft.LOVE20_TOKEN_ADDRESS());
        love20Payment.setSymbol("TestLOVE20");

        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        TokenMainManager manager =
            new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol));
        MockERC20Payment token = new MockERC20Payment();
        token.setSymbol("A");

        string memory name = groupNft.groupNameOf(manager.activate(address(token)));
        _assertStartsWith(name, "Testtm_");
        assertEq(bytes(name).length, 11);
        _assertHexFrom(name, 7);
    }

    function testT180_managerTypeCodesAreNonEmptyAndDistinct() public {
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        address[4] memory managers = [
            address(new TokenMainManager(address(chat), address(0), address(0), address(0), address(protocol))),
            address(new TokenGovManager(address(chat), address(0), address(0), address(0), address(protocol))),
            address(
                new TokenActionMainManager(address(chat), address(0), address(0), address(0), address(protocol), 3)
            ),
            address(
                new TokenActionGovManager(address(chat), address(0), address(0), address(0), address(protocol), 3)
            )
        ];

        bytes32[4] memory seen;
        for (uint256 i = 0; i < managers.length; i++) {
            string memory typeCode = IManagerBase(managers[i]).TYPE_CODE();
            assertTrue(bytes(typeCode).length != 0);

            bytes32 typeCodeHash = keccak256(bytes(typeCode));
            for (uint256 j = 0; j < i; j++) {
                assertTrue(typeCodeHash != seen[j]);
            }
            seen[i] = typeCodeHash;
        }
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

    function _repeatAscii(string memory value, uint256 count) internal pure returns (string memory) {
        bytes memory valueBytes = bytes(value);
        bytes memory result = new bytes(count * valueBytes.length);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = valueBytes[i % valueBytes.length];
        }
        return string(result);
    }

    function _assertHexFrom(string memory value, uint256 start) internal pure {
        bytes memory valueBytes = bytes(value);
        assertTrue(valueBytes.length > start);
        for (uint256 i = start; i < valueBytes.length; i++) {
            bytes1 char = valueBytes[i];
            assertTrue((char >= "0" && char <= "9") || (char >= "a" && char <= "f"));
        }
    }

    function _assertTokenGroupActivated(
        Vm.Log[] memory logs,
        address manager,
        address token,
        uint256 activatedGroupId,
        address operator
    ) internal pure {
        Vm.Log memory log = logs[logs.length - 1];
        assertEq(log.emitter, manager);
        assertEq(log.topics[0], TOKEN_GROUP_ACTIVATED_SIG);
        assertEq(log.topics[1], _topicAddress(token));
        assertEq(log.topics[2], bytes32(activatedGroupId));
        assertEq(log.topics[3], _topicAddress(operator));
        assertEq(log.data.length, 0);
    }

    function _assertTokenActionGroupActivated(
        Vm.Log[] memory logs,
        address manager,
        address token,
        uint256 actionId,
        uint256 activatedGroupId,
        address operator
    ) internal pure {
        Vm.Log memory log = logs[logs.length - 1];
        assertEq(log.emitter, manager);
        assertEq(log.topics[0], TOKEN_ACTION_GROUP_ACTIVATED_SIG);
        assertEq(log.topics[1], _topicAddress(token));
        assertEq(log.topics[2], bytes32(actionId));
        assertEq(log.topics[3], bytes32(activatedGroupId));
        assertEq(abi.decode(log.data, (address)), operator);
    }

    function _topicAddress(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}
