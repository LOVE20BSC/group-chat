// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IPostScopeSource} from "../sources/IPostScopeSource.sol";
import {IBanVoteWeightSource} from "../sources/ban/IBanVoteWeightSource.sol";

interface IBaseManagerErrors {
    error ManagerDependencyNotContract(address dependency);
    error AlreadyManaged(uint256 groupId);
    error ZeroRecentRounds();
    error ManagerGroupNameUnavailable();
    error ManagerMintCostChanged(uint256 expected, uint256 actual);
    error TokenNotLOVE20(address token);
    error UnexpectedManagerERC721Received(address operator, address from, uint256 tokenId);
    error ManagerGroupNameSpaceTooSmall(uint256 maxNameLength, uint256 required);
}

interface IBaseManager is IPostScopeSource, IBanVoteWeightSource, IERC721Receiver, IBaseManagerErrors {
    function GROUP_CHAT_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function BAN_SOURCE_ADDRESS() external view returns (address);

    function BEFORE_POST_PLUGIN_ADDRESS() external view returns (address);

    function AFTER_POST_PLUGIN_ADDRESS() external view returns (address);
}
