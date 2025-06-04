// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "contracts/v1/lib/LinkedList.sol";

contract LinkedListTest is Test {
    using LinkedList for mapping(uint64 => uint64);

    mapping(uint64 => uint64) list;

    function setUp() public {
        // Reset list before each test
        list[0] = 0;
    }

    function testInsertIntoEmptyList() public {
        list.insertWhenZeroAsRoot(5);
        assertEq(list[0], 5, "First element should be 5");
        assertEq(list[5], 0, "Next element should be 0");
    }

    function testInsertMultipleOrdered() public {
        list.insertWhenZeroAsRoot(5);
        list.insertWhenZeroAsRoot(3);
        list.insertWhenZeroAsRoot(7);

        // Check order: 3 -> 5 -> 7
        assertEq(list[0], 3, "First element should be 3");
        assertEq(list[3], 5, "Second element should be 5");
        assertEq(list[5], 7, "Third element should be 7");
        assertEq(list[7], 0, "Last element should point to 0");
    }

    function testInsertDuplicate() public {
        list.insertWhenZeroAsRoot(5);
        list.insertWhenZeroAsRoot(5); // Should be ignored

        assertEq(list[0], 5, "First element should still be 5");
        assertEq(list[5], 0, "Should still point to 0");
    }

    function testPopFromEmptyList() public {
        list.popWhenZeroAsRoot();
        assertEq(list[0], 0, "Empty list should remain empty");
    }

    function testPopSingleElement() public {
        list.insertWhenZeroAsRoot(5);
        list.popWhenZeroAsRoot();

        assertEq(list[0], 0, "List should be empty after pop");
        assertTrue(list[5] == 0, "Popped element should be cleared");
    }

    function testPopFromMultipleElements() public {
        list.insertWhenZeroAsRoot(5);
        list.insertWhenZeroAsRoot(3);
        list.insertWhenZeroAsRoot(7);

        list.popWhenZeroAsRoot();

        // After popping 3, should be: 5 -> 7
        assertEq(list[0], 5, "New first element should be 5");
        assertEq(list[5], 7, "Second element should be 7");
        assertEq(list[7], 0, "Last element should point to 0");
        assertTrue(list[3] == 0, "Popped element should be cleared");
    }
}
