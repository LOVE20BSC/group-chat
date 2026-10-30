// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {ManagerBase} from "./ManagerBase.sol";
import {IPhase} from "@core/interfaces/IPhase.sol";
import {ILaunch} from "@core/interfaces/ILaunch.sol";
import {IStake} from "@core/interfaces/IStake.sol";
import {IVote} from "@core/interfaces/IVote.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract TokenManagerBase is ManagerBase {
    address public immutable STAKE_ADDRESS;
    address public immutable LAUNCH_ADDRESS;
    address public immutable PHASE_ADDRESS;

    constructor(
        address groupChat_,
        address banSource_,
        address beforePostPlugin_,
        address afterPostPlugin_,
        address actionTarget_
    ) ManagerBase(groupChat_, banSource_, beforePostPlugin_, afterPostPlugin_, actionTarget_) {
        STAKE_ADDRESS = IVote(VOTE_ADDRESS).STAKE_ADDRESS();
        LAUNCH_ADDRESS = IStake(STAKE_ADDRESS).LAUNCH_ADDRESS();
        PHASE_ADDRESS = IStake(STAKE_ADDRESS).PHASE_ADDRESS();
    }

    function _requireLOVE20Token(address token) internal view {
        if (token.code.length == 0 || !ILaunch(LAUNCH_ADDRESS).isLOVE20Token(token)) {
            revert TokenNotLOVE20(token);
        }
    }

    /// @dev The vote weight a manager reports is the one the community holds now, matching the old
    ///      protocol's live reads, so every consumer resolves the phase's current round through here.
    function currentPhase() public view returns (uint256) {
        return IPhase(PHASE_ADDRESS).currentPhase();
    }

    function _tokenNamePayload(address token) internal view returns (string memory) {
        return string(_sanitizeNameSymbol(IERC20Metadata(token).symbol()));
    }

    function _sanitizeNameSymbol(string memory rawSymbol) internal pure returns (bytes memory) {
        bytes memory input = bytes(rawSymbol);
        bytes memory output = new bytes(input.length);
        uint256 outputLength = 0;
        uint256 i = 0;

        while (i < input.length) {
            bytes1 char = input[i];
            if ((char >= 0x30 && char <= 0x39) || (char >= 0x41 && char <= 0x5A) || (char >= 0x61 && char <= 0x7A)) {
                output[outputLength] = char;
                outputLength++;
                i++;
                continue;
            }

            if (i + 2 < input.length) {
                bytes1 byte2 = input[i + 1];
                bytes1 byte3 = input[i + 2];
                if (
                    char >= 0xE4 && char <= 0xE9 && byte2 >= 0x80 && byte2 <= 0xBF && byte3 >= 0x80
                        && byte3 <= 0xBF && !(char == 0xE4 && byte2 < 0xB8)
                ) {
                    output[outputLength] = input[i];
                    output[outputLength + 1] = input[i + 1];
                    output[outputLength + 2] = input[i + 2];
                    outputLength += 3;
                    i += 3;
                    continue;
                }
            }

            i++;
        }

        bytes memory trimmed = new bytes(outputLength);
        for (uint256 j = 0; j < outputLength; j++) {
            trimmed[j] = output[j];
        }
        return trimmed;
    }
}
