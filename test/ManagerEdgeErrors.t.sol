// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IManagerBaseErrors} from "../src/interfaces/managers/IManagerBase.sol";
import {MockERC20Payment} from "./mocks/MockLOVE20Group.sol";
import {MockManager} from "./mocks/MockManagers.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {TestBase} from "./utils/TestBase.sol";

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

    function testT161_managerReportsMintCostChanged() public {
        MockManagerMemberNFT memberNFT = new MockManagerMemberNFT(false, 1);
        MockManagerGroupChat groupChat = new MockManagerGroupChat(address(memberNFT));
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockManager manager =
            new MockManager(address(groupChat), address(0), address(0), address(0), address(protocol));

        vm.expectRevert(abi.encodeWithSelector(IManagerBaseErrors.ManagerMintCostChanged.selector, 0, 1));
        manager.activateMockManagedGroup();
    }
}
