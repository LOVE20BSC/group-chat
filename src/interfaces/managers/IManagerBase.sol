// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IPostScopeSource} from "../sources/IPostScopeSource.sol";
import {IBanVoteWeightSource} from "../sources/ban/IBanVoteWeightSource.sol";

interface IManagerBaseErrors {
    error AlreadyManaged(uint256 groupId);
    error ManagerGroupNameUnavailable();
    error ManagerMintCostChanged(
        uint256 expected,
        uint256 actual
    );
    error TokenNotLOVE20(address tokenAddress);
    error UnexpectedManagerERC721Received(
        address operator,
        address from,
        uint256 tokenId
    );
}

interface IManagerBase is IPostScopeSource, IBanVoteWeightSource, IERC721Receiver, IManagerBaseErrors {
    function GROUP_CHAT_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function TYPE_CODE() external view returns (string memory);

    function BAN_SOURCE_ADDRESS() external view returns (address);

    function BEFORE_POST_PLUGIN_ADDRESS() external view returns (address);

    function AFTER_POST_PLUGIN_ADDRESS() external view returns (address);
}
