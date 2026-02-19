// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISupraSValueFeed {
    // Data structure to hold the pair data
    struct priceFeed {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }

    // Function to retrieve the data for a single data pair
    function getSvalue(uint256 _pairIndex) external view returns (priceFeed memory);
}
