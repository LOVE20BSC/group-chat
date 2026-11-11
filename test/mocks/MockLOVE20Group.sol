// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract MockLOVE20Group {
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

    function setMaxGroupNameLength(uint256 maxGroupNameLength) external {
        MAX_GROUP_NAME_LENGTH = maxGroupNameLength;
    }

    function mint(address to) external returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _owners[tokenId] = to;
    }

    function mint(string calldata groupName) external returns (uint256 tokenId, uint256 cost) {
        require(bytes(groupName).length <= MAX_GROUP_NAME_LENGTH, "NAME_TOO_LONG");
        string memory nameKey = _nameKey(groupName);
        require(_nameToTokenId[nameKey] == 0, "NAME_USED");

        cost = mintCost;
        if (cost != 0) {
            IERC20(LOVE20_TOKEN_ADDRESS).transferFrom(msg.sender, address(this), cost);
        }

        tokenId = _nextTokenId++;
        _owners[tokenId] = msg.sender;
        _groupNames[tokenId] = groupName;
        _nameToTokenId[nameKey] = tokenId;
    }

    function calculateMintCost(string memory) external view returns (uint256) {
        return mintCost;
    }

    function MAX_NAME_LENGTH() external view returns (uint256) {
        return MAX_GROUP_NAME_LENGTH;
    }

    function _nameKey(string memory name) internal pure returns (string memory) {
        bytes memory input = bytes(name);
        bytes memory out = new bytes(input.length);
        for (uint256 i = 0; i < input.length; i++) {
            bytes1 char = input[i];
            out[i] = (char >= 0x41 && char <= 0x5A) ? bytes1(uint8(char) + 32) : char;
        }
        return string(out);
    }

    function isNameUsed(string calldata groupName) external view returns (bool) {
        return _nameToTokenId[_nameKey(groupName)] != 0;
    }

    function isGroupNameUsed(string calldata groupName) external view returns (bool) {
        return _nameToTokenId[_nameKey(groupName)] != 0;
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
}

contract MockERC20Payment {
    enum ApproveMode {
        Normal,
        ReturnFalse,
        Revert
    }

    string public symbol = "LOVE20";
    ApproveMode public approveMode;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function setSymbol(string calldata symbol_) external {
        symbol = symbol_;
    }

    function setApproveMode(ApproveMode approveMode_) external {
        approveMode = approveMode_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (approveMode == ApproveMode.ReturnFalse) {
            return false;
        }
        if (approveMode == ApproveMode.Revert) {
            revert("APPROVE");
        }
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
