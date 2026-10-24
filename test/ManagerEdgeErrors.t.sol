// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IBaseManagerErrors} from "../src/interfaces/managers/IBaseManager.sol";
import {MockManager} from "./mocks/MockManagers.sol";
import {MockLOVE20Protocols} from "./mocks/MockLOVE20Protocols.sol";
import {TestBase} from "./utils/TestBase.sol";

contract MockManagerMemberNFT {
    address public constant LOVE20_TOKEN_ADDRESS = address(0);
    uint256 public constant MAX_NAME_LENGTH = 64;

    bool internal immutable _nameUsed;
    uint256 internal immutable _actualCost;

    constructor(bool nameUsed_, uint256 actualCost_) {
        _nameUsed = nameUsed_;
        _actualCost = actualCost_;
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

contract MockManagerActionTarget {
    address public immutable submitAddress;
    address public immutable voteAddress;

    constructor(address submitAddress_, address voteAddress_) {
        submitAddress = submitAddress_;
        voteAddress = voteAddress_;
    }
}

contract ManagerEdgeErrorsTest is TestBase {
    function testT160_managerReportsGroupNameUnavailable() public {
        MockManagerMemberNFT memberNFT = new MockManagerMemberNFT(true, 0);
        MockManagerGroupChat groupChat = new MockManagerGroupChat(address(memberNFT));
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockManager manager =
            new MockManager(address(groupChat), address(0), address(0), address(0), address(protocol));

        vm.expectRevert(abi.encodeWithSelector(IBaseManagerErrors.ManagerGroupNameUnavailable.selector));
        manager.activateMockManagedGroup();
    }

    function testT161_managerReportsMintCostChanged() public {
        MockManagerMemberNFT memberNFT = new MockManagerMemberNFT(false, 1);
        MockManagerGroupChat groupChat = new MockManagerGroupChat(address(memberNFT));
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();
        MockManager manager =
            new MockManager(address(groupChat), address(0), address(0), address(0), address(protocol));

        vm.expectRevert(abi.encodeWithSelector(IBaseManagerErrors.ManagerMintCostChanged.selector, 0, 1));
        manager.activateMockManagedGroup();
    }

    function testT162_managerRejectsZeroRequiredDependencies() public {
        MockManagerMemberNFT memberNFT = new MockManagerMemberNFT(false, 0);
        MockManagerGroupChat groupChat = new MockManagerGroupChat(address(memberNFT));
        MockLOVE20Protocols protocol = new MockLOVE20Protocols();

        vm.expectRevert(
            abi.encodeWithSelector(IBaseManagerErrors.ManagerDependencyNotContract.selector, address(0))
        );
        new MockManager(address(0), address(0), address(0), address(0), address(protocol));

        vm.expectRevert(
            abi.encodeWithSelector(IBaseManagerErrors.ManagerDependencyNotContract.selector, address(0))
        );
        new MockManager(address(groupChat), address(0), address(0), address(0), address(0));

        MockManagerGroupChat zeroMemberNFTGroupChat = new MockManagerGroupChat(address(0));
        vm.expectRevert(
            abi.encodeWithSelector(IBaseManagerErrors.ManagerDependencyNotContract.selector, address(0))
        );
        new MockManager(address(zeroMemberNFTGroupChat), address(0), address(0), address(0), address(protocol));

        MockManagerActionTarget zeroSubmit = new MockManagerActionTarget(address(0), address(protocol));
        vm.expectRevert(
            abi.encodeWithSelector(IBaseManagerErrors.ManagerDependencyNotContract.selector, address(0))
        );
        new MockManager(address(groupChat), address(0), address(0), address(0), address(zeroSubmit));

        MockManagerActionTarget zeroVote = new MockManagerActionTarget(address(protocol), address(0));
        vm.expectRevert(
            abi.encodeWithSelector(IBaseManagerErrors.ManagerDependencyNotContract.selector, address(0))
        );
        new MockManager(address(groupChat), address(0), address(0), address(0), address(zeroVote));
    }
}
