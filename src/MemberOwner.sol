// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IMemberNFT} from "core/src/interfaces/IMemberNFT.sol";

library MemberOwner {
    // Load-bearing: an absent id yields address(0). Callers turn that into a failed code check, an
    // authorization miss, or a `GroupNotExist` revert. If ownerOf ever returned a non-zero owner for
    // an absent id, the code-check callers would answer true and the views would silently report
    // live data for a group that does not exist.
    function ofOrZero(address memberNFT, uint256 memberId) internal view returns (address owner) {
        try IMemberNFT(memberNFT).ownerOf(memberId) returns (address resolved) {
            return resolved;
        } catch {
            return address(0);
        }
    }
}
