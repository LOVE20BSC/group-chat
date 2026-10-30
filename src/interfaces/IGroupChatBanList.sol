// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IGroupChatBanListErrors {
    error NotGroupOperator(
        uint256 groupId,
        uint256 operatorId
    );
    error ZeroTargetSenderId();
    error DuplicateMemberId(uint256 memberId);
}

interface IGroupChatBanListEvents {
    event SenderBanChanged(
        uint256 indexed groupId,
        uint256 indexed targetSenderId,
        uint256 operatorId,
        address indexed operator,
        bool listed
    );
}

interface IGroupChatBanList is IGroupChatBanListErrors, IGroupChatBanListEvents {
    function GROUP_ADMIN_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function GROUP_DELEGATE_ADDRESS() external view returns (address);

    function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool);

    function isSenderIdBannedBatch(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned);

    function senderIdBanDetails(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned, address[] memory operatorAddresses, uint256[] memory operatorIds);

    function banBySenderIds(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds) external;

    function unbanBySenderIds(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds) external;

    function senderIdBanList(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (
            uint256[] memory senderIdList,
            address[] memory operatorAddresses,
            uint256[] memory operatorIds,
            uint256 totalCount
        );
}
