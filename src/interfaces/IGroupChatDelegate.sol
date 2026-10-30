// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IGroupChatDelegateErrors {
    error GroupNotExist(uint256 groupId);
    error NotGroupOwner(uint256 groupId);
    error NotMemberOwner(uint256 memberId);
    error DelegateNotAcceptingNewDelegations(uint256 delegateId);
    error DelegateIsSelfGroup(uint256 groupId);
}

interface IGroupChatDelegateEvents {
    event DelegateChanged(
        uint256 indexed groupId,
        uint256 indexed delegateId,
        address indexed owner,
        address ownerSnapshot,
        address delegateOwnerSnapshot,
        uint256 prevDelegateId,
        address prevOwnerSnapshot,
        address prevDelegateOwnerSnapshot
    );

    event DelegationCleared(
        uint256 indexed groupId,
        uint256 indexed delegateId,
        address indexed delegateOwner,
        address prevOwnerSnapshot,
        address prevDelegateOwnerSnapshot
    );

    event DelegationAcceptanceChanged(
        uint256 indexed delegateId,
        address indexed delegateOwner,
        bool enabled
    );
}

interface IGroupChatDelegate is IGroupChatDelegateErrors, IGroupChatDelegateEvents {
    function GROUP_ADDRESS() external view returns (address);

    function setDelegateId(uint256 groupId, uint256 delegateId) external;

    function clearDelegatedGroupIds(uint256 delegateId, uint256[] calldata groupIds) external;

    function setDelegationAcceptanceEnabled(uint256 delegateId, bool enabled) external;

    function isDelegationAcceptanceEnabled(uint256 delegateId) external view returns (bool);

    function effectiveDelegateId(uint256 groupId) external view returns (uint256);

    function effectiveDelegateIdsByGroupIds(uint256[] calldata groupIds)
        external
        view
        returns (uint256[] memory delegateIds);

    function delegatedGroupIds(uint256 delegateId, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory groupIdList, bool[] memory isEffective, uint256 totalCount);

    function ownerOrDelegateId(uint256 groupId, address operatorAddress) external view returns (uint256);
}
