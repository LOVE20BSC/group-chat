// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC721Receiver} from "../external/IERC721Receiver.sol";

import {IPostScopeSource} from "../sources/IPostScopeSource.sol";
import {IBanVoteWeightSource} from "../sources/ban/IBanVoteWeightSource.sol";

interface IBaseManager is IPostScopeSource, IBanVoteWeightSource, IERC721Receiver {
    error ManagerAddressHasNoCode();
    error AlreadyManaged();
    error RecentRoundsZero();
    error ManagerGroupNameUnavailable();
    error ManagerMintCostChanged();
    error ManagerPaymentFailed();
    error ManagerApprovalFailed();
    error TokenNotLOVE20();
    error UnexpectedManagerERC721Received();
    error ActionIdNotExist();

    function GROUP_CHAT_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function EXTENSION_CENTER_ADDRESS() external view returns (address);

    function BAN_SOURCE_ADDRESS() external view returns (address);

    function BEFORE_POST_PLUGIN_ADDRESS() external view returns (address);

    function AFTER_POST_PLUGIN_ADDRESS() external view returns (address);
}
