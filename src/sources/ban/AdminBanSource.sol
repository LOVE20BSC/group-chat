// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupBanList} from "../../interfaces/IGroupBanList.sol";
import {IAdminBanSource} from "../../interfaces/sources/ban/IAdminBanSource.sol";

contract AdminBanSource is IAdminBanSource {
    address public immutable GROUP_BAN_LIST_ADDRESS;

    constructor(address groupBanList_) {
        if (groupBanList_.code.length == 0) {
            revert AdminBanSourceAddressHasNoCode();
        }
        GROUP_BAN_LIST_ADDRESS = groupBanList_;
    }

    function isBanned(uint256 groupId, uint256 senderId, address senderAddress) external view returns (bool) {
        return IGroupBanList(GROUP_BAN_LIST_ADDRESS).isBanned(groupId, senderId, senderAddress);
    }
}
