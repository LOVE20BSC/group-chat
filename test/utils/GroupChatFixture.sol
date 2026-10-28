// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {GroupAdmin} from "../../src/GroupAdmin.sol";
import {GroupChat} from "../../src/GroupChat.sol";
import {IGroupChat} from "../../src/interfaces/IGroupChat.sol";

import {MockGroupDelegate} from "../mocks/MockGroupDelegate.sol";
import {MockLOVE20Group} from "../mocks/MockLOVE20Group.sol";
import {MockPhase} from "../mocks/MockPhase.sol";
import {TestBase, Vm} from "./TestBase.sol";

abstract contract GroupChatFixture is TestBase {
    MockLOVE20Group internal groupNft;
    MockPhase internal phase;
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
    bytes32 internal constant SCOPE_SOURCE_CHANGED_SIG =
        keccak256("ScopeSourceChanged(uint256,address,uint256,address,address)");
    bytes32 internal constant BAN_SOURCE_CHANGED_SIG =
        keccak256("BanSourceChanged(uint256,address,uint256,address,address)");
    bytes32 internal constant BEFORE_POST_PLUGIN_CHANGED_SIG =
        keccak256("BeforePostPluginChanged(uint256,address,uint256,address,address)");
    bytes32 internal constant AFTER_POST_PLUGIN_CHANGED_SIG =
        keccak256("AfterPostPluginChanged(uint256,address,uint256,address,address)");
    bytes32 internal constant GROUP_CHAT_ACTIVATED_SIG =
        keccak256("GroupChatActivated(uint256,uint256,address,bool,address,address,address,address)");
    bytes32 internal constant POSTING_ALLOWED_CHANGED_SIG =
        keccak256("PostingAllowedChanged(uint256,uint256,address,bool)");
    bytes32 internal constant MESSAGE_POSTED_SIG =
        keccak256("MessagePosted(uint256,uint256,uint256,address,uint256,uint256,bool,bool,string)");
    bytes32 internal constant SENDER_MENTIONED_SIG = keccak256("SenderMentioned(uint256,uint256,uint256)");
    bytes32 internal constant AFTER_POST_PLUGIN_FAILED_SIG =
        keccak256("AfterPostPluginFailed(uint256,uint256,uint256,address,bytes32,uint256,bytes4)");

    function setUp() public virtual {
        groupNft = new MockLOVE20Group();
        groupId = groupNft.mint(chatOwner);
        senderId = groupNft.mint(senderOwner);
        otherGroupId = groupNft.mint(other);
        delegateId = groupNft.mint(delegateIdOwner);

        originBlocks = block.number + 50;
        phase = new MockPhase(originBlocks, phaseBlocks);
        groupDelegate = new MockGroupDelegate(address(groupNft));
        baseGroupAdmin = new GroupAdmin(address(groupDelegate), 20);
        chat = new GroupChat(address(baseGroupAdmin), address(phase), maxContentLength, maxMentionedSenderIds);
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

    function _canPostAllowed(uint256 groupId_, uint256 senderId_) internal view returns (bool allowed) {
        (allowed,) = chat.canPost(groupId_, senderId_);
    }

    function _canPost(uint256 groupId_, uint256 senderId_)
        internal
        view
        returns (bool allowed, IGroupChat.PostRejectionReason reason)
    {
        return chat.canPost(groupId_, senderId_);
    }

    function _activateEmpty() internal {
        vm.prank(chatOwner);
        chat.activateChat(groupId, address(0), address(0), address(0), address(0));
    }

    function _decodeAddress(bytes memory data) internal pure returns (address value) {
        value = abi.decode(data, (address));
    }

    function _decodeMessagePostedData(bytes memory data)
        internal
        pure
        returns (
            address sender,
            uint256 round,
            uint256 quotedMessageId,
            bool hasQuote,
            bool mentionAll,
            string memory content
        )
    {
        return abi.decode(data, (address, uint256, uint256, bool, bool, string));
    }

    function _decodeFailAfterPostPluginRound(bytes memory data) internal pure returns (uint256 round) {
        (round,,,) = abi.decode(data, (uint256, bytes32, uint256, bytes4));
    }
}
