// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function expectRevert(bytes4) external;
    function expectRevert(bytes calldata) external;
    function prank(address) external;
    function roll(uint256) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool value) internal pure {
        require(value, "ASSERT_TRUE");
    }

    function assertEq(uint256 left, uint256 right) internal pure {
        require(left == right, "ASSERT_EQ_UINT");
    }

    function assertEq(address left, address right) internal pure {
        require(left == right, "ASSERT_EQ_ADDRESS");
    }

    function assertEq(bytes32 left, bytes32 right) internal pure {
        require(left == right, "ASSERT_EQ_BYTES32");
    }

    function assertEq(bool left, bool right) internal pure {
        require(left == right, "ASSERT_EQ_BOOL");
    }

    function assertEq(bytes memory left, bytes memory right) internal pure {
        require(keccak256(left) == keccak256(right), "ASSERT_EQ_BYTES");
    }

    function assertEq(string memory left, string memory right) internal pure {
        require(keccak256(bytes(left)) == keccak256(bytes(right)), "ASSERT_EQ_STRING");
    }
}
