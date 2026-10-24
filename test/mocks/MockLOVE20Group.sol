// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract MockLOVE20Group {
    bytes4 internal constant TEST_PREFIX = bytes4("Test");

    uint256 internal _nextTokenId = 1;
    address public LOVE20_TOKEN_ADDRESS;
    uint256 public mintCost;
    uint256 public MAX_GROUP_NAME_LENGTH = 32;
    mapping(uint256 => address) internal _owners;
    mapping(uint256 => string) internal _groupNames;
    mapping(string => uint256) internal _nameToTokenId;

    constructor() {
        LOVE20_TOKEN_ADDRESS = address(new MockERC20Payment());
    }

    function setMintPayment(address love20TokenAddress, uint256 mintCost_) external {
        LOVE20_TOKEN_ADDRESS = love20TokenAddress;
        mintCost = mintCost_;
    }

    function setMaxGroupNameLength(uint256 maxGroupNameLength_) external {
        MAX_GROUP_NAME_LENGTH = maxGroupNameLength_;
    }

    function mint(address to) external returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _owners[tokenId] = to;
    }

    function mint(string calldata groupName) external returns (uint256 tokenId, uint256 cost) {
        string memory normalizedGroupName = _canonicalizeGroupName(groupName);
        require(bytes(normalizedGroupName).length <= MAX_GROUP_NAME_LENGTH, "NAME_TOO_LONG");
        require(_nameToTokenId[normalizedGroupName] == 0, "NAME_USED");

        cost = mintCost;
        if (cost != 0) {
            IERC20Metadata(LOVE20_TOKEN_ADDRESS).transferFrom(msg.sender, address(this), cost);
        }

        tokenId = _nextTokenId++;
        _owners[tokenId] = msg.sender;
        _groupNames[tokenId] = normalizedGroupName;
        _nameToTokenId[normalizedGroupName] = tokenId;
    }

    function calculateMintCost(string memory) external view returns (uint256) {
        return mintCost;
    }

    function MAX_NAME_LENGTH() external view returns (uint256) {
        return MAX_GROUP_NAME_LENGTH;
    }

    function isNameUsed(string calldata groupName) external view returns (bool) {
        return _nameToTokenId[_canonicalizeGroupName(groupName)] != 0;
    }

    function isGroupNameUsed(string calldata groupName) external view returns (bool) {
        return _nameToTokenId[_canonicalizeGroupName(groupName)] != 0;
    }

    function groupNameOf(uint256 tokenId) external view returns (string memory) {
        return _groupNames[tokenId];
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        owner = _owners[tokenId];
        if (owner == address(0)) revert IERC721Errors.ERC721NonexistentToken(tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_owners[tokenId] == from, "NOT_OWNER");
        _owners[tokenId] = to;
    }

    function _canonicalizeGroupName(string memory groupName) internal view returns (string memory) {
        address love20 = LOVE20_TOKEN_ADDRESS;
        if (bytes4(bytes(IERC20Metadata(love20).symbol())) != TEST_PREFIX || _hasTestPrefix(groupName)) {
            return groupName;
        }
        return string(abi.encodePacked("Test", groupName));
    }

    function _hasTestPrefix(string memory groupName) internal pure returns (bool) {
        bytes memory nameBytes = bytes(groupName);
        return nameBytes.length >= 4 && nameBytes[0] == "T" && nameBytes[1] == "e" && nameBytes[2] == "s"
            && nameBytes[3] == "t";
    }
}

contract MockERC20Payment {
    string public symbol = "LOVE20";
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function setSymbol(string calldata symbol_) external {
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
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
}
