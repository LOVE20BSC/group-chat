// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface Vm {
    function envAddress(string calldata name) external returns (address);

    function envString(string calldata name) external returns (string memory);

    function envUint(string calldata name) external returns (uint256);

    function envOr(string calldata name, string calldata defaultValue) external returns (string memory);

    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);

    function envOr(string calldata name, address defaultValue) external returns (address);

    function startBroadcast() external;

    function stopBroadcast() external;

    function createDir(string calldata path, bool recursive) external;

    function writeFile(string calldata path, string calldata data) external;

    function toString(address value) external pure returns (string memory);

    function toString(uint256 value) external pure returns (string memory);
}

abstract contract ScriptBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
}
