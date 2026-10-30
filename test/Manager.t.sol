// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChat, IGroupChatErrors} from "../src/interfaces/IGroupChat.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IManagerBaseErrors} from "../src/interfaces/managers/IManagerBase.sol";

import {MockERC20Payment} from "./mocks/MockLOVE20Group.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {MockManager} from "./mocks/MockManagers.sol";
import {MockBeforePostRejectPlugin, MockPostBanSource} from "./mocks/MockPlugins.sol";
import {GroupChatFixture} from "./utils/GroupChatFixture.sol";

contract ManagerTest is GroupChatFixture {
    MockLOVE20Protocols internal managerCenter;

    function setUp() public override {
        super.setUp();
        managerCenter = new MockLOVE20Protocols();
    }

    function testT100_managerActivatesChatWithImmutableConfigAndNoDelegate() public {
        MockPostBanSource banSource = new MockPostBanSource();
        MockBeforePostRejectPlugin beforePlugin = new MockBeforePostRejectPlugin();
        MockManager manager = new MockManager(
            address(chat), address(banSource), address(beforePlugin), address(0), address(managerCenter)
        );

        groupId = manager.activateMockManagedGroup();
        assertEq(chat.chatInfo(groupId).owner, address(manager));

        assertTrue(chat.chatInfo(groupId).activated);
        assertTrue(chat.chatInfo(groupId).postingAllowed);
        IGroupChat.ChatInfo memory info = chat.chatInfo(groupId);
        assertEq(info.scopeSource, address(manager));
        assertEq(info.banSource, address(banSource));
        assertEq(info.beforePostPlugin, address(beforePlugin));
        assertEq(info.afterPostPlugin, address(0));

        assertTrue(manager.isSenderAllowed(groupId, senderId));
        assertEq(manager.voteWeight(groupId, senderId), 1);
    }

    function testT101_managerOwnerCannotStopPostingThroughGroupChat() public {
        MockManager manager = new MockManager(address(chat), address(0), address(0), address(0), address(managerCenter));

        groupId = manager.activateMockManagedGroup();

        vm.prank(chatOwner);
        vm.expectRevert(abi.encodeWithSelector(IGroupChatErrors.NotGroupOperator.selector, groupId, groupId));
        chat.setPostingAllowed(groupId, groupId, false);
    }

    function testT102_managerDoesNotExposeReconfigureEntrypoints() public {
        MockManager manager = new MockManager(address(chat), address(0), address(0), address(0), address(managerCenter));

        _expectUnknownSelector(
            address(manager), abi.encodeWithSignature("setPostingAllowed(uint256,uint256,bool)", groupId, groupId, false)
        );
        _expectUnknownSelector(
            address(manager), abi.encodeWithSignature("setScopeSource(uint256,uint256,address)", groupId, groupId, other)
        );
        _expectUnknownSelector(
            address(manager), abi.encodeWithSignature("setBanSource(uint256,uint256,address)", groupId, groupId, other)
        );
        _expectUnknownSelector(
            address(manager),
            abi.encodeWithSignature("setBeforePostPlugin(uint256,uint256,address)", groupId, groupId, other)
        );
        _expectUnknownSelector(
            address(manager),
            abi.encodeWithSignature("setAfterPostPlugin(uint256,uint256,address)", groupId, groupId, other)
        );
        _expectUnknownSelector(address(manager), abi.encodeWithSignature("setDelegateId(uint256,uint256)", groupId, 0));
    }

    function testT103_managerDoesNotExposeGenericCallEntrypoints() public {
        MockManager manager = new MockManager(address(chat), address(0), address(0), address(0), address(managerCenter));

        _expectUnknownSelector(address(manager), abi.encodeWithSignature("call(address,bytes)", other, ""));
        _expectUnknownSelector(address(manager), abi.encodeWithSignature("delegatecall(address,bytes)", other, ""));
        _expectUnknownSelector(
            address(manager), abi.encodeWithSignature("execute(address,uint256,bytes)", other, 0, "")
        );
    }

    function testT104_managerReceivesErc721() public {
        MockManager manager = new MockManager(address(chat), address(0), address(0), address(0), address(managerCenter));

        vm.expectRevert(
            abi.encodeWithSelector(IManagerBaseErrors.UnexpectedManagerERC721Received.selector, chatOwner, address(0), groupId)
        );
        manager.onERC721Received(chatOwner, address(0), groupId, "");

        vm.prank(address(groupNft));
        vm.expectRevert(
            abi.encodeWithSelector(
                IManagerBaseErrors.UnexpectedManagerERC721Received.selector, chatOwner, chatOwner, groupId
            )
        );
        manager.onERC721Received(chatOwner, chatOwner, groupId, "");

        vm.prank(address(groupNft));
        bytes4 received = manager.onERC721Received(chatOwner, address(0), groupId, "");
        assertEq(received, IERC721Receiver.onERC721Received.selector);
    }

    function testT105_managerPullsMintCostAndPaysGroupNft() public {
        MockERC20Payment token = new MockERC20Payment();
        groupNft.setMintPayment(address(token), 10);
        token.mint(address(this), 10);

        MockManager manager = new MockManager(address(chat), address(0), address(0), address(0), address(managerCenter));
        token.approve(address(manager), 10);

        groupId = manager.activateMockManagedGroup();

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(manager)), 0);
        assertEq(token.balanceOf(address(groupNft)), 10);
        assertEq(chat.chatInfo(groupId).owner, address(manager));
    }

    function _expectUnknownSelector(address target, bytes memory data) internal {
        (bool ok,) = target.call(data);
        assertTrue(!ok);
    }
}
