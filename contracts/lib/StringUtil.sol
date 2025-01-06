// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library StringUtil {
    function contact(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
}
