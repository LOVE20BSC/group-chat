// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupAdmin} from "../../src/GroupAdmin.sol";
import {GroupChat} from "../../src/GroupChat.sol";
import {IGroupChatErrors} from "../../src/interfaces/IGroupChat.sol";

import {MockGroupDefaults} from "../mocks/MockGroupDefaults.sol";
import {MockGroupDelegate} from "../mocks/MockGroupDelegate.sol";
import {MockLOVE20Group} from "../mocks/MockLOVE20Group.sol";
import {TestBase, Vm} from "./TestBase.sol";

abstract contract GroupChatFixture is TestBase {
    MockLOVE20Group internal groupNft;
    MockGroupDefaults internal groupDefaults;
    MockGroupDelegate internal groupDelegate;
    GroupAdmin internal baseGroupAdmin;
    GroupChat internal chat;

    address internal chatOwner = address(0xA11CE);
    address internal senderOwner = address(0xB0B);
    address internal other = address(0xCAFE);
    address internal delegateIdOwner = address(0xD36E6A7E);

    uint256 internal groupId;
    uint256 internal senderId;
    uint256 internal otherGroupId;
    uint256 internal delegateId;
    uint256 internal originBlocks;
    uint256 internal phaseBlocks = 100;
    uint256 internal maxContentLength = 4096;
    uint256 internal maxMentionedSenderIds = 32;
    bytes32 internal constant SET_SCOPE_SOURCE_SIG = keccak256("SetScopeSource(uint256,address,address,address)");
    bytes32 internal constant SET_BAN_SOURCE_SIG = keccak256("SetBanSource(uint256,address,address,address)");
    bytes32 internal constant SET_BEFORE_POST_PLUGIN_SIG =
        keccak256("SetBeforePostPlugin(uint256,address,address,address)");
    bytes32 internal constant SET_AFTER_POST_PLUGIN_SIG =
        keccak256("SetAfterPostPlugin(uint256,address,address,address)");
    bytes32 internal constant ACTIVATE_SIG = keccak256("Activate(uint256,address)");
    bytes32 internal constant SET_POSTING_ALLOWED_SIG = keccak256("SetPostingAllowed(uint256,address,bool)");
    bytes32 internal constant POST_MESSAGE_SIG = keccak256("PostMessage(uint256,uint256,address,uint256,uint256)");
    bytes32 internal constant MENTION_SENDER_ID_SIG = keccak256("MentionSenderId(uint256,uint256,uint256)");
    bytes32 internal constant MENTION_ALL_SIG = keccak256("MentionAll(uint256,uint256)");
    bytes32 internal constant FAIL_AFTER_POST_PLUGIN_SIG =
        keccak256("FailAfterPostPlugin(uint256,uint256,address,uint256,bytes)");
    bytes32 internal constant SET_DEFAULT_GROUP_ID_SIG = keccak256("SetDefaultGroupId(address,uint256)");
    bytes32 internal constant CLEAR_DEFAULT_GROUP_ID_SIG = keccak256("ClearDefaultGroupId(address,uint256)");

    function setUp() public virtual {
        groupNft = new MockLOVE20Group();
        groupId = groupNft.mint(chatOwner);
        senderId = groupNft.mint(senderOwner);
        otherGroupId = groupNft.mint(other);
        delegateId = groupNft.mint(delegateIdOwner);

        originBlocks = block.number + 50;
        groupDefaults = new MockGroupDefaults(address(groupNft));
        groupDelegate = new MockGroupDelegate(address(groupNft));
        baseGroupAdmin = new GroupAdmin(address(groupDefaults), address(groupDelegate), 20);
        chat = new GroupChat(
            address(baseGroupAdmin), originBlocks, phaseBlocks, maxContentLength, maxMentionedSenderIds
        );
    }

    function _emptyMentionedSenderIds() internal pure returns (uint256[] memory mentionedSenderIds) {
        mentionedSenderIds = new uint256[](0);
    }

    function _post(uint256 groupId_, uint256 senderId_, string memory content) internal {
        chat.post(groupId_, senderId_, content, _emptyMentionedSenderIds(), false, 0);
    }

    function _postWithMentionedSenderIds(
        uint256 groupId_,
        uint256 senderId_,
        string memory content,
        uint256[] memory mentionedSenderIds,
        bool mentionAll
    ) internal {
        chat.post(groupId_, senderId_, content, mentionedSenderIds, mentionAll, 0);
    }

    function _postWithQuote(uint256 groupId_, uint256 senderId_, string memory content, uint256 quotedMessageId)
        internal
    {
        chat.post(groupId_, senderId_, content, _emptyMentionedSenderIds(), false, quotedMessageId);
    }

    function _postAsDefaultSender(uint256 groupId_, string memory content) internal {
        chat.postAsDefaultSender(groupId_, content, _emptyMentionedSenderIds(), false, 0);
    }

    function _canPostAllowed(uint256 groupId_, uint256 senderId_, address senderAddress_)
        internal
        view
        returns (bool allowed)
    {
        (allowed,) = chat.canPost(groupId_, senderId_, senderAddress_);
    }

    function _canPost(uint256 groupId_, uint256 senderId_, address senderAddress_)
        internal
        view
        returns (bool allowed, bytes4 reasonCode)
    {
        return chat.canPost(groupId_, senderId_, senderAddress_);
    }

    function _activateEmpty() internal {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));
    }

    function _decodeAddress(bytes memory data) internal pure returns (address value) {
        value = abi.decode(data, (address));
    }

    function _decodePostMessage(bytes memory data) internal pure returns (uint256 round, uint256 messageId) {
        (round, messageId) = abi.decode(data, (uint256, uint256));
    }

    function _decodeMessageId(bytes memory data) internal pure returns (uint256 messageId) {
        messageId = abi.decode(data, (uint256));
    }

    function _decodeFailAfterPostPluginRound(bytes memory data) internal pure returns (uint256 round) {
        (round,) = abi.decode(data, (uint256, bytes));
    }
}
