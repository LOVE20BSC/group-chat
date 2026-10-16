// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

library EnumerableSets {
    struct AddressSet {
        address[] values;
        mapping(address => uint256) indexPlusOne;
    }

    struct UintSet {
        uint256[] values;
        mapping(uint256 => uint256) indexPlusOne;
    }

    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return set.indexPlusOne[value] != 0;
    }

    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return set.indexPlusOne[value] != 0;
    }

    function add(AddressSet storage set, address value) internal returns (bool) {
        if (contains(set, value)) {
            return false;
        }
        set.values.push(value);
        set.indexPlusOne[value] = set.values.length;
        return true;
    }

    function add(UintSet storage set, uint256 value) internal returns (bool) {
        if (contains(set, value)) {
            return false;
        }
        set.values.push(value);
        set.indexPlusOne[value] = set.values.length;
        return true;
    }

    function remove(AddressSet storage set, address value) internal returns (bool) {
        uint256 indexPlusOne = set.indexPlusOne[value];
        if (indexPlusOne == 0) {
            return false;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = set.values.length - 1;
        if (index != lastIndex) {
            address last = set.values[lastIndex];
            set.values[index] = last;
            set.indexPlusOne[last] = indexPlusOne;
        }
        set.values.pop();
        delete set.indexPlusOne[value];
        return true;
    }

    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        uint256 indexPlusOne = set.indexPlusOne[value];
        if (indexPlusOne == 0) {
            return false;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = set.values.length - 1;
        if (index != lastIndex) {
            uint256 last = set.values[lastIndex];
            set.values[index] = last;
            set.indexPlusOne[last] = indexPlusOne;
        }
        set.values.pop();
        delete set.indexPlusOne[value];
        return true;
    }

    function page(AddressSet storage set, uint256 offset, uint256 limit) internal view returns (address[] memory) {
        uint256 count = pageCount(set.values.length, offset, limit);
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = set.values[offset + i];
        }
        return result;
    }

    function page(UintSet storage set, uint256 offset, uint256 limit) internal view returns (uint256[] memory) {
        uint256 count = pageCount(set.values.length, offset, limit);
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = set.values[offset + i];
        }
        return result;
    }

    function pageCount(uint256 total, uint256 offset, uint256 limit) internal pure returns (uint256) {
        if (limit == 0 || offset >= total) {
            return 0;
        }

        uint256 remaining = total - offset;
        return remaining < limit ? remaining : limit;
    }
}
