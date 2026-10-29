// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IGroupMemberErrors {
    error NotGroupOperator(
        uint256 groupId,
        uint256 operatorId
    );
    error DuplicateMemberId(uint256 memberId);
}

interface IGroupMemberEvents {
    event MemberStatusChanged(
        uint256 indexed groupId,
        uint256 indexed memberId,
        uint256 operatorId,
        address indexed operator,
        bool listed
    );
}

interface IGroupMember is IGroupMemberErrors, IGroupMemberEvents {
    function GROUP_ADMIN_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function addMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIds_) external;

    function removeMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIds_) external;

    function isMemberId(uint256 groupId, uint256 memberId) external view returns (bool);

    function isMemberIdBatch(uint256 groupId, uint256[] calldata memberIds_)
        external
        view
        returns (bool[] memory listed);

    function memberIdsCount(uint256 groupId) external view returns (uint256);

    function memberIds(uint256 groupId, uint256 offset, uint256 limit) external view returns (uint256[] memory);
}
