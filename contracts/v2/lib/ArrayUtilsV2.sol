// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ArrayUtilsV2 {
    error IndexOutOfBounds();

    function indexOf(address[] storage arr, address value) internal view returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                return i;
            }
        }
        revert IndexOutOfBounds();
    }

    function remove(address[] storage arr, uint256 index) internal {
        for (uint256 i = index; i < arr.length - 1; ++i) {
            arr[i] = arr[i + 1];
        }
        arr.pop();
    }

    function sum(uint128[] memory values) internal pure returns (uint128 total) {
        for (uint256 i = 0; i < values.length; ++i) {
            total += values[i];
        }
    }

    function sum(uint256[] memory values) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < values.length; ++i) {
            total += values[i];
        }
    }
}
