// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupAdmin {
    error GroupAdminAddressHasNoCode();
    error UnauthorizedGroupAdminManager();
    error GroupNotExist();
    error DuplicateAdminId();
    error AdminIdsLimitExceeded();
    error MaxAdminIdsZero();
    error GroupDelegateGroupMismatch();

    event SetAdmin(
        uint256 indexed groupId, address indexed operator, uint256 indexed adminId, uint256 operatorId, bool listed
    );

    event SetAdminSnapshot(
        uint256 indexed groupId,
        address indexed operator,
        uint256 indexed adminId,
        uint256 operatorId,
        address groupOwnerSnapshot,
        address adminOwnerSnapshot
    );

    function GROUP_DEFAULTS_ADDRESS() external view returns (address);

    function GROUP_DELEGATE_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function MAX_ADMIN_IDS() external view returns (uint256);

    function addAdmins(uint256 groupId, uint256[] calldata adminIdList) external;

    function removeAdmins(uint256 groupId, uint256[] calldata adminIdList) external;

    function adminIdOf(uint256 groupId, address account) external view returns (uint256);

    function ownerOrDelegateIdOf(uint256 groupId, address account) external view returns (uint256);

    function isAdminId(uint256 groupId, uint256 adminId) external view returns (bool);

    function adminIds(uint256 groupId) external view returns (uint256[] memory ids, bool[] memory isEffective);
}
