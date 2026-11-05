// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {MemberNFT} from "@core/MemberNFT.sol";

import {IManagerBaseErrors} from "../src/interfaces/managers/IManagerBase.sol";
import {MockERC20Payment} from "./mocks/MockLOVE20Group.sol";
import {MockManager} from "./mocks/MockManagers.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {TestBase} from "./utils/TestBase.sol";

contract MockLOVE20Token {
    string public symbol = "LOVE20";
    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOWANCE");
        require(balanceOf[from] >= amount, "BALANCE");
        allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "BALANCE");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
    }
}

contract MockManagerMemberNFT {
    address public immutable LOVE20_TOKEN_ADDRESS;
    uint256 public constant MAX_NAME_LENGTH = 32;

    bool internal immutable _nameUsed;
    uint256 internal immutable _actualCost;

    constructor(bool nameUsed, uint256 actualCost) {
        LOVE20_TOKEN_ADDRESS = address(new MockERC20Payment());
        _nameUsed = nameUsed;
        _actualCost = actualCost;
    }

    function isNameUsed(string calldata) external view returns (bool) {
        return _nameUsed;
    }

    function calculateMintCost(string calldata) external pure returns (uint256) {
        return 0;
    }

    function mint(string calldata) external view returns (uint256 id, uint256 cost) {
        return (1, _actualCost);
    }
}

contract MockManagerGroupChat {
    address public immutable GROUP_ADDRESS;

    constructor(address memberNFT) {
        GROUP_ADDRESS = memberNFT;
    }

    function activateChat(uint256, address, address, address, address) external {}
}

contract ManagerEdgeErrorsTest is TestBase {
    function testT160_managerReportsGroupNameUnavailable() public {
        MockManagerMemberNFT memberNFT = new MockManagerMemberNFT(true, 0);
        MockManagerGroupChat groupChat = new MockManagerGroupChat(address(memberNFT));
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockManager manager =
            new MockManager(address(groupChat), address(0), address(0), address(0), address(protocol));

        vm.expectRevert(abi.encodeWithSelector(IManagerBaseErrors.ManagerGroupNameUnavailable.selector));
        manager.activateMockManagedGroup();
    }

    function testT161_managerChargesQuotedMintCost() public {
        MockLOVE20Token payment = new MockLOVE20Token();
        MemberNFT memberNFT = new MemberNFT(100, 32, 1, 32);
        memberNFT.init(address(payment));
        MockManagerGroupChat groupChat = new MockManagerGroupChat(address(memberNFT));
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockManager manager =
            new MockManager(address(groupChat), address(0), address(0), address(0), address(protocol));

        payment.mint(address(this), 100);
        uint256 quotedMintCost = memberNFT.calculateMintCost("mk_mock_manager_0000");
        payment.approve(address(manager), quotedMintCost);

        uint256 balanceBefore = payment.balanceOf(address(this));
        uint256 groupId = manager.activateMockManagedGroup();

        assertEq(balanceBefore - payment.balanceOf(address(this)), quotedMintCost);
        assertEq(payment.balanceOf(address(manager)), 0);
        assertEq(payment.balanceOf(address(memberNFT)), 0);
        assertEq(payment.totalSupply(), 100 - quotedMintCost);
        assertEq(memberNFT.ownerOf(groupId), address(manager));
    }
}
