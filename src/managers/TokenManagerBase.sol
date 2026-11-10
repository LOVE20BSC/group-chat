// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {ManagerBase} from "./ManagerBase.sol";
import {IStake} from "@core/interfaces/IStake.sol";
import {ILaunch} from "@core/interfaces/ILaunch.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract TokenManagerBase is ManagerBase {
    constructor(
        address groupChatAddress,
        address banSourceAddress,
        address beforePostPluginAddress,
        address afterPostPluginAddress,
        address actionTargetAddress
    ) ManagerBase(
        groupChatAddress,
        banSourceAddress,
        beforePostPluginAddress,
        afterPostPluginAddress,
        actionTargetAddress
    ) {}

    // 两类 Manager 共用的权重分母：只依赖 STAKE 与 phase，token 地址由各自映射给出。
    function totalVoteWeight(uint256 groupId) external view returns (uint256) {
        address tokenAddress = _managedTokenAddress(groupId);
        if (tokenAddress == address(0)) {
            return 0;
        }
        return IStake(STAKE_ADDRESS).totalValidGovVotes(tokenAddress, currentPhase());
    }

    // 命名与铸造骨架：Test 前缀判定 → stem → 唯一名 → mint，两类 Manager 只差 payload。
    function _mintManagedGroupForPayload(string memory payload) internal returns (uint256 groupId) {
        bool requiresTestPrefix = _love20TokenRequiresTestPrefix();
        (string memory stem, uint256 randomHexLength) = _managedGroupNameStem(payload, requiresTestPrefix);
        return _mintManagedGroup(stem, randomHexLength, requiresTestPrefix);
    }

    function _managedTokenAddress(uint256 groupId) internal view virtual returns (address);

    function _checkLOVE20Token(address tokenAddress) internal view {
        if (tokenAddress.code.length == 0 || !ILaunch(LAUNCH_ADDRESS).isLOVE20Token(tokenAddress)) {
            revert TokenNotLOVE20(tokenAddress);
        }
    }

    function _tokenNamePayload(address tokenAddress) internal view returns (string memory) {
        return string(_sanitizeNameSymbol(IERC20Metadata(tokenAddress).symbol()));
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
