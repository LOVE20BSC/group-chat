// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IAdminBanSource} from "../../interfaces/sources/ban/IAdminBanSource.sol";
import {IGroupChatBanList} from "../../interfaces/IGroupChatBanList.sol";

contract AdminBanSource is IAdminBanSource {
    address public immutable GROUP_BAN_LIST_ADDRESS;

    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address groupBanListAddress) {
        GROUP_BAN_LIST_ADDRESS = groupBanListAddress;
    }

    function isBanned(uint256 groupId, uint256 senderId) external view returns (bool) {
        return IGroupChatBanList(GROUP_BAN_LIST_ADDRESS).isSenderIdBanned(groupId, senderId);
    }
}
