// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IGroupAdminErrors {
    error NotGroupOperator(uint256 groupId, uint256 operatorId);
    error GroupNotExist(uint256 groupId);
    error DuplicateMemberId(uint256 memberId);
    error AdminIdsLimitExceeded(uint256 groupId, uint256 count, uint256 maxCount);
}

interface IGroupAdminEvents {
    event AdminChanged(
        uint256 indexed groupId,
        uint256 indexed adminId,
        uint256 operatorId,
        address indexed operator,
        bool listed,
        address groupOwnerSnapshot,
        address adminOwnerSnapshot,
        bool prevListed,
        address prevGroupOwnerSnapshot,
        address prevAdminOwnerSnapshot
    );
}

interface IGroupAdmin is IGroupAdminErrors, IGroupAdminEvents {
    function GROUP_DELEGATE_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function MAX_ADMIN_IDS() external view returns (uint256);

    function addAdmins(uint256 groupId, uint256 operatorId, uint256[] calldata adminIds_) external;

    function removeAdmins(uint256 groupId, uint256 operatorId, uint256[] calldata adminIds_) external;

    function isAdminId(uint256 groupId, uint256 adminId) external view returns (bool);

    function adminIds(uint256 groupId) external view returns (uint256[] memory ids, bool[] memory isEffective);
}
