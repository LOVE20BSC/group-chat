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

// OZ 5.5 的 SafeERC20 对「token 自己 revert」原样冒泡，只有「调用成功但返回 false」才包成
// SafeERC20FailedOperation；这个替身覆盖后者，两种失败路径都要各有一条断言。
contract MockFalseReturnERC20 {
    string public symbol = "LOVE20";

    function balanceOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract ManagerTest is GroupChatFixture {
    MockLOVE20Protocols internal managerCenter;

    function setUp() public override {
        super.setUp();
        managerCenter = new MockLOVE20Protocols();
    }

    function testT100_managerActivatesChatWithImmutableConfig() public {
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

    function testT106_managerPaymentFailureRollsBackMintAndActivation() public {
        MockERC20Payment token = new MockERC20Payment();
        groupNft.setMintPayment(address(token), 10);
        token.mint(address(this), 10);
        uint256 supplyBefore = groupNft.totalSupply();

        MockManager manager = new MockManager(address(chat), address(0), address(0), address(0), address(managerCenter));

        // No approval on purpose. A reverting token bubbles its own revert data through SafeERC20.
        vm.expectRevert(bytes("ALLOWANCE"));
        manager.activateMockManagedGroup();

        // A failed payment must roll back the whole activation: no charge, no NFT, no Chat.
        assertEq(groupNft.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(address(this)), 10);
        assertEq(token.balanceOf(address(manager)), 0);
        assertEq(token.balanceOf(address(groupNft)), 0);
    }

    function testT107_managerPaymentFailureOnInsufficientBalance() public {
        MockERC20Payment token = new MockERC20Payment();
        groupNft.setMintPayment(address(token), 10);
        uint256 supplyBefore = groupNft.totalSupply();

        MockManager manager = new MockManager(address(chat), address(0), address(0), address(0), address(managerCenter));
        token.mint(address(this), 5);
        token.approve(address(manager), 10);

        vm.expectRevert(bytes("BALANCE"));
        manager.activateMockManagedGroup();

        assertEq(groupNft.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(address(this)), 5);
        assertEq(token.balanceOf(address(groupNft)), 0);
    }

    function testT108_managerPaymentFailureOnFalseReturnToken() public {
        MockFalseReturnERC20 token = new MockFalseReturnERC20();
        groupNft.setMintPayment(address(token), 10);
        uint256 supplyBefore = groupNft.totalSupply();

        MockManager manager = new MockManager(address(chat), address(0), address(0), address(0), address(managerCenter));

        // A non-reverting token answering false is the case SafeERC20 does wrap.
        vm.expectRevert(abi.encodeWithSignature("SafeERC20FailedOperation(address)", address(token)));
        manager.activateMockManagedGroup();

        assertEq(groupNft.totalSupply(), supplyBefore);
    }

    function _expectUnknownSelector(address target, bytes memory data) internal {
        (bool ok, bytes memory returnData) = target.call(data);
        assertTrue(!ok);
        // An absent selector reverts with empty data; a present entry that is merely rejected (for
        // example by an auth modifier) returns data. Without this the "no new entries" check passes
        // for both cases and proves nothing.
        assertEq(returnData.length, 0);
    }
}
