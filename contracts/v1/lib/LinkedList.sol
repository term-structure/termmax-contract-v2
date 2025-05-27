// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title LinkedList
/// @author Term Structure Labs
/// @notice A linked list library
library LinkedList {
    function insertWhenZeroAsRoot(mapping(uint64 => uint64) storage s, uint64 value) internal {
        uint64 prev = 0;
        uint64 current = s[0];

        // find insert position
        while (current != 0 && current < value) {
            prev = current;
            current = s[current];
        }

        // ignore if value exists
        if (current == value) {
            return;
        }

        // insert node
        s[value] = current;
        s[prev] = value;
    }

    function popWhenZeroAsRoot(mapping(uint64 => uint64) storage s) internal {
        uint64 first = s[0];
        if (first != 0) {
            // update head
            s[0] = s[first];
            // delete node
            delete s[first];
        }
    }
}
