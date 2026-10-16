// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPostBanSource} from "../IPostBanSource.sol";

interface IGovVotedBanSource is IPostBanSource {
    error GovVotedBanSourceAddressHasNoCode();
    error BanVoteWeightSourceUnavailable();
    error TargetAddressZero();
    error TargetSenderIdZero();
    error VoteWeightZero();
    error VoteUnchanged();
    error VoteNotFound();
    error BanThresholdTooHigh();
    error MinSupportToOpposeRatioZero();

    event SetAddressBanVote(
        uint256 indexed groupId,
        address indexed targetAddress,
        address indexed voter,
        bool supportBan,
        uint256 settledWeight,
        uint256 supportWeight,
        uint256 opposeWeight,
        uint256 stateVersion
    );

    event SetSenderIdBanVote(
        uint256 indexed groupId,
        uint256 indexed targetSenderId,
        address indexed voter,
        bool supportBan,
        uint256 settledWeight,
        uint256 supportWeight,
        uint256 opposeWeight,
        uint256 stateVersion
    );

    event SetAddressBan(uint256 indexed groupId, address indexed targetAddress, bool listed, uint256 stateVersion);

    event SetSenderIdBan(uint256 indexed groupId, uint256 indexed targetSenderId, bool listed, uint256 stateVersion);

    event ChangeStateVersion(uint256 indexed groupId, uint256 stateVersion);

    function GROUP_ADDRESS() external view returns (address);

    function PRECISION() external view returns (uint256);

    function MIN_SUPPORT_TO_OPPOSE_RATIO() external view returns (uint256);

    function BAN_THRESHOLD_RATIO() external view returns (uint256);

    function voteBySenderAddress(uint256 groupId, address senderAddress, bool supportBan) external;

    function clearVoteBySenderAddress(uint256 groupId, address senderAddress) external;

    function refreshVoteBySenderAddress(uint256 groupId, address senderAddress, address voter) external;

    function voteBySenderId(uint256 groupId, uint256 senderId, bool supportBan) external;

    function clearVoteBySenderId(uint256 groupId, uint256 senderId) external;

    function refreshVoteBySenderId(uint256 groupId, uint256 senderId, address voter) external;

    function voteBySender(uint256 groupId, uint256 senderId, address senderAddress, bool supportBan) external;

    function clearVoteBySender(uint256 groupId, uint256 senderId, address senderAddress) external;

    function refreshVoteBySender(uint256 groupId, uint256 senderId, address senderAddress, address voter) external;

    function voteWeightsBySenderAddressesByVoter(uint256 groupId, address[] calldata senderAddresses, address voter)
        external
        view
        returns (uint256[] memory supportWeights, uint256[] memory opposeWeights);

    function voteStatusBySenderAddress(uint256 groupId, address senderAddress)
        external
        view
        returns (bool banned, uint256 supportWeight, uint256 opposeWeight);

    function voteStatusBySenderAddresses(uint256 groupId, address[] calldata senderAddresses)
        external
        view
        returns (bool[] memory banned, uint256[] memory supportWeights, uint256[] memory opposeWeights);

    function isAddressBanned(uint256 groupId, address senderAddress) external view returns (bool);

    function isAddressBannedBatch(uint256 groupId, address[] calldata senderAddresses)
        external
        view
        returns (bool[] memory banned);

    function votedSenderAddressesCount(uint256 groupId) external view returns (uint256);

    function votedSenderAddresses(uint256 groupId, uint256 offset, uint256 limit)
        external
        view
        returns (
            address[] memory senderAddresses,
            uint256[] memory supportWeights,
            uint256[] memory opposeWeights,
            uint256[] memory voterCounts
        );

    function votersBySenderAddressCount(uint256 groupId, address senderAddress) external view returns (uint256);

    function votersBySenderAddress(uint256 groupId, address senderAddress, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory voters, uint256[] memory supportWeights, uint256[] memory opposeWeights);

    function voteWeightsBySenderIdsByVoter(uint256 groupId, uint256[] calldata senderIds, address voter)
        external
        view
        returns (uint256[] memory supportWeights, uint256[] memory opposeWeights);

    function voteStatusBySenderId(uint256 groupId, uint256 senderId)
        external
        view
        returns (bool banned, uint256 supportWeight, uint256 opposeWeight);

    function voteStatusBySenderIds(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned, uint256[] memory supportWeights, uint256[] memory opposeWeights);

    function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool);

    function isSenderIdBannedBatch(uint256 groupId, uint256[] calldata senderIds)
        external
        view
        returns (bool[] memory banned);

    function votedSenderIdsCount(uint256 groupId) external view returns (uint256);

    function votedSenderIds(uint256 groupId, uint256 offset, uint256 limit)
        external
        view
        returns (
            uint256[] memory senderIds,
            uint256[] memory supportWeights,
            uint256[] memory opposeWeights,
            uint256[] memory voterCounts
        );

    function votersBySenderIdCount(uint256 groupId, uint256 senderId) external view returns (uint256);

    function votersBySenderId(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory voters, uint256[] memory supportWeights, uint256[] memory opposeWeights);

    function stateVersion(uint256 groupId) external view returns (uint256);
}
