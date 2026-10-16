// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPostBanSource} from "../IPostBanSource.sol";

interface IAdminBanSource is IPostBanSource {
    error AdminBanSourceAddressHasNoCode();

    function GROUP_BAN_LIST_ADDRESS() external view returns (address);
}
