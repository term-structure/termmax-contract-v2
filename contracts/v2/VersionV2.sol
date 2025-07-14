// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract VersionV2 {
    // Function to get the version number
    function getVersion() external pure returns (string memory) {
        return "2.0.0";
    }
}
