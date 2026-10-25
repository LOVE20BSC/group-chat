// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IGroupChat} from "../interfaces/IGroupChat.sol";
import {IManagerBase} from "../interfaces/managers/IManagerBase.sol";
import {IActionTarget} from "@action/interfaces/IActionTarget.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IMemberNFT} from "@core/interfaces/IMemberNFT.sol";

abstract contract ManagerBase is IManagerBase {
    using SafeERC20 for IERC20;

    address public immutable GROUP_CHAT_ADDRESS;
    address public immutable GROUP_ADDRESS;
    uint256 internal immutable MAX_NAME_LENGTH;
    address public immutable BAN_SOURCE_ADDRESS;
    address public immutable BEFORE_POST_PLUGIN_ADDRESS;
    address public immutable AFTER_POST_PLUGIN_ADDRESS;

    bytes4 internal constant TEST_PREFIX = bytes4("Test");
    bytes16 internal constant HEX_SYMBOLS = "0123456789abcdef";
    uint256 internal constant GROUP_NAME_RANDOM_HEX_LENGTH = 4;
    uint256 internal constant GROUP_NAME_SEPARATOR_BYTES = 1;
    uint256 internal constant GROUP_NAME_TEST_PREFIX_BYTES = 4;

    address internal immutable ACTION_TARGET_ADDRESS;
    address internal immutable VOTE_ADDRESS;

    uint256 internal _mintNonce;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_
    ) {
        address memberNFT = IGroupChat(groupChat_).GROUP_ADDRESS();
        address vote = IActionTarget(actionTarget_).voteAddress();
        GROUP_CHAT_ADDRESS = groupChat_;
        GROUP_ADDRESS = memberNFT;
        MAX_NAME_LENGTH = IMemberNFT(memberNFT).MAX_NAME_LENGTH();
        BAN_SOURCE_ADDRESS = banSource_;
        BEFORE_POST_PLUGIN_ADDRESS = beforePostPlugin_;
        AFTER_POST_PLUGIN_ADDRESS = afterPostPlugin_;
        ACTION_TARGET_ADDRESS = actionTarget_;
        VOTE_ADDRESS = vote;
    }

    function TYPE_CODE() external view returns (string memory) {
        return _typeCode();
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (msg.sender != GROUP_ADDRESS || from != address(0)) {
            revert UnexpectedManagerERC721Received(operator, from, tokenId);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    function _mintManagedGroup(
        string memory groupNameStem,
        uint256 randomHexLength,
        bool requiresTestPrefix
    ) internal returns (uint256 groupId) {
        string memory groupName = _nextGroupName(groupNameStem, randomHexLength, requiresTestPrefix);
        IMemberNFT memberNFT = IMemberNFT(GROUP_ADDRESS);

        uint256 expectedMintCost = memberNFT.calculateMintCost(groupName);
        if (expectedMintCost != 0) {
            address love20 = memberNFT.LOVE20_TOKEN_ADDRESS();
            IERC20(love20).safeTransferFrom(msg.sender, address(this), expectedMintCost);
            IERC20(love20).forceApprove(GROUP_ADDRESS, expectedMintCost);
        }

        uint256 actualMintCost;
        (groupId, actualMintCost) = memberNFT.mint(groupName);
        if (actualMintCost != expectedMintCost) {
            revert ManagerMintCostChanged(expectedMintCost, actualMintCost);
        }
    }

    function _activateManagedGroup(uint256 groupId) internal {
        IGroupChat(GROUP_CHAT_ADDRESS).activateChat(
            groupId, address(this), BAN_SOURCE_ADDRESS, BEFORE_POST_PLUGIN_ADDRESS, AFTER_POST_PLUGIN_ADDRESS
        );
    }

    function _requireNotManaged(uint256 managedGroupId) internal pure {
        if (managedGroupId != 0) {
            revert AlreadyManaged(managedGroupId);
        }
    }

    function _typeCode() internal view virtual returns (string memory);

    function _managedGroupNameStem(string memory payload, bool requiresTestPrefix)
        internal
        view
        returns (string memory stem, uint256 randomHexLength)
    {
        string memory typeCode = _typeCode();
        uint256 fixedBytes = bytes(typeCode).length + GROUP_NAME_SEPARATOR_BYTES * 2
            + GROUP_NAME_RANDOM_HEX_LENGTH + (requiresTestPrefix ? GROUP_NAME_TEST_PREFIX_BYTES : 0);

        if (bytes(payload).length != 0 && fixedBytes + bytes(payload).length <= MAX_NAME_LENGTH) {
            return (string(abi.encodePacked(typeCode, "_", payload)), GROUP_NAME_RANDOM_HEX_LENGTH);
        }

        randomHexLength = MAX_NAME_LENGTH - bytes(typeCode).length - GROUP_NAME_SEPARATOR_BYTES
            - (requiresTestPrefix ? GROUP_NAME_TEST_PREFIX_BYTES : 0);
        return (typeCode, randomHexLength);
    }

    function _nextGroupName(
        string memory groupNameStem,
        uint256 randomHexLength,
        bool requiresTestPrefix
    ) internal returns (string memory) {
        for (uint256 i = 0; i < 8; i++) {
            string memory randomHex = _randomHex(randomHexLength, _mintNonce);
            string memory groupName = _canonicalizeGroupName(
                string(abi.encodePacked(groupNameStem, "_", randomHex)), requiresTestPrefix
            );
            unchecked {
                _mintNonce++;
            }
            if (!IMemberNFT(GROUP_ADDRESS).isNameUsed(groupName)) {
                return groupName;
            }
        }
        revert ManagerGroupNameUnavailable();
    }

    function _love20TokenRequiresTestPrefix() internal view returns (bool) {
        address love20 = IMemberNFT(GROUP_ADDRESS).LOVE20_TOKEN_ADDRESS();
        return bytes4(bytes(IERC20Metadata(love20).symbol())) == TEST_PREFIX;
    }

    function _canonicalizeGroupName(string memory groupName, bool requiresTestPrefix)
        internal
        pure
        returns (string memory)
    {
        if (!requiresTestPrefix || _hasTestPrefix(groupName)) {
            return groupName;
        }
        return string(abi.encodePacked("Test", groupName));
    }

    function _hasTestPrefix(string memory groupName) internal pure returns (bool) {
        bytes memory nameBytes = bytes(groupName);
        return nameBytes.length >= 4 && nameBytes[0] == "T" && nameBytes[1] == "e" && nameBytes[2] == "s"
            && nameBytes[3] == "t";
    }

    function _randomHex(uint256 hexLength, uint256 nonce) internal view returns (string memory) {
        bytes memory buffer = new bytes(hexLength);
        uint256 offset = 0;
        uint256 chunkIndex = 0;

        while (offset < hexLength) {
            bytes32 randomHash = keccak256(
                abi.encodePacked(block.chainid, address(this), msg.sender, block.number, nonce, chunkIndex)
            );
            uint256 chunkLength = hexLength - offset > 64 ? 64 : hexLength - offset;
            for (uint256 i = 0; i < chunkLength; i++) {
                uint8 value = uint8(randomHash[i / 2]);
                buffer[offset + i] = i % 2 == 0 ? HEX_SYMBOLS[value >> 4] : HEX_SYMBOLS[value & 0x0f];
            }
            offset += chunkLength;
            chunkIndex++;
        }

        return string(buffer);
    }
}
