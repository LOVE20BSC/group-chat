// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IAdminBanSource} from "../../interfaces/sources/ban/IAdminBanSource.sol";
import {IGroupChatBanList} from "../../interfaces/IGroupChatBanList.sol";

contract AdminBanSource is IAdminBanSource {
    address public immutable GROUP_BAN_LIST_ADDRESS;

    constructor(address groupBanList_) {
        GROUP_BAN_LIST_ADDRESS = groupBanList_;
    }

    function isBanned(uint256 groupId, uint256 senderId) external view returns (bool) {
        return IGroupChatBanList(GROUP_BAN_LIST_ADDRESS).isSenderIdBanned(groupId, senderId);
    }
}
