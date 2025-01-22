// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ArrayUtils {
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
}
