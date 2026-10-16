// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IExtensionCenter} from "../interfaces/external/IExtensionCenter.sol";
import {ILOVE20Launch} from "../interfaces/external/ILOVE20Launch.sol";
import {ILOVE20Stake} from "../interfaces/external/ILOVE20Stake.sol";
import {BaseManager} from "./BaseManager.sol";

abstract contract BaseTokenManager is BaseManager {
    address internal immutable LAUNCH_ADDRESS;
    address internal immutable STAKE_ADDRESS;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address extensionCenter_
    ) BaseManager(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, extensionCenter_) {
        address launch = IExtensionCenter(extensionCenter_).launchAddress();
        address stake = IExtensionCenter(extensionCenter_).stakeAddress();
        _requireCode(launch);
        _requireCode(stake);

        LAUNCH_ADDRESS = launch;
        STAKE_ADDRESS = stake;
    }

    function _tokenGovVoteWeight(address token, address account) internal view returns (uint256) {
        return ILOVE20Stake(STAKE_ADDRESS).validGovVotes(token, account);
    }

    function _requireLOVE20Token(address token) internal view {
        _requireCode(token);
        if (!ILOVE20Launch(LAUNCH_ADDRESS).isLOVE20Token(token)) {
            revert TokenNotLOVE20();
        }
    }
}
