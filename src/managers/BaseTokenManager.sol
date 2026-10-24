// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {BaseManager} from "./BaseManager.sol";
import {ILaunch} from "@core/interfaces/ILaunch.sol";
import {IStake} from "@core/interfaces/IStake.sol";
import {IVote} from "@core/interfaces/IVote.sol";

abstract contract BaseTokenManager is BaseManager {
    address internal immutable STAKE_ADDRESS;
    address internal immutable LAUNCH_ADDRESS;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_
    ) BaseManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, actionTarget_) {
        STAKE_ADDRESS = IVote(VOTE_ADDRESS).stakeAddress();
        LAUNCH_ADDRESS = IStake(STAKE_ADDRESS).launchAddress();
        _requireCode(STAKE_ADDRESS);
        _requireCode(LAUNCH_ADDRESS);
    }

    function _tokenGovVoteWeight(address token, uint256 memberId) internal view returns (uint256) {
        return IStake(STAKE_ADDRESS).validGovVotes(token, memberId);
    }

    function _requireLOVE20Token(address token) internal view {
        _requireCode(token);
        if (!ILaunch(LAUNCH_ADDRESS).isLOVE20Token(token)) {
            revert TokenNotLOVE20(token);
        }
    }
}
