// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupBanList {
    error GroupBanListAddressHasNoCode();
    error UnauthorizedGroupBanListManager();
    error TargetAddressZero();
    error TargetSenderIdZero();
    error SenderPairLengthMismatch();

    event SetAddressBan(
        uint256 indexed groupId,
        address indexed operatorAddress,
        address indexed targetAddress,
        uint256 operatorId,
        bool listed
    );

    event SetSenderIdBan(
        uint256 indexed groupId,
        address indexed operatorAddress,
        uint256 indexed targetSenderId,
        uint256 operatorId,
        bool listed
    );

    function GROUP_ADMIN_ADDRESS() external view returns (address);

    function isAddressBanned(uint256 groupId, address senderAddress) external view returns (bool);

    function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool);

    function addressBanDetails(uint256 groupId, address[] calldata senderAddresses)
        external
        view
        returns (bool[] memory banned, address[] memory operatorAddresses, uint256[] memory operatorIds);

    function senderIdBanDetails(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned, address[] memory operatorAddresses, uint256[] memory operatorIds);

    function banBySenderAddresses(uint256 groupId, address[] calldata senderAddresses) external;

    function unbanBySenderAddresses(uint256 groupId, address[] calldata senderAddresses) external;

    function addressBanListCount(uint256 groupId) external view returns (uint256);

    function addressBanList(uint256 groupId, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory senderAddresses, address[] memory operatorAddresses, uint256[] memory operatorIds);

    function banBySenderIds(uint256 groupId, uint256[] calldata senderIds) external;

    function unbanBySenderIds(uint256 groupId, uint256[] calldata senderIds) external;

    function banBySenders(uint256 groupId, uint256[] calldata senderIds, address[] calldata senderAddresses) external;

    function unbanBySenders(uint256 groupId, uint256[] calldata senderIds, address[] calldata senderAddresses)
        external;

    function senderIdBanListCount(uint256 groupId) external view returns (uint256);

    function senderIdBanList(uint256 groupId, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory senderIds, address[] memory operatorAddresses, uint256[] memory operatorIds);

    function isBanned(uint256 groupId, uint256 senderId, address senderAddress) external view returns (bool);
}
