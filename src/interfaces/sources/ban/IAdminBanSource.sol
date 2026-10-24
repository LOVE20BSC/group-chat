// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IPostBanSource} from "../IPostBanSource.sol";

interface IAdminBanSourceErrors {
    error GroupBanListNotContract(address dependency);
}

interface IAdminBanSource is IPostBanSource, IAdminBanSourceErrors {
    function GROUP_BAN_LIST_ADDRESS() external view returns (address);
}
