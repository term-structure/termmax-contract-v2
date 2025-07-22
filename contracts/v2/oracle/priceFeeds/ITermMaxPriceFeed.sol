// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title The customized price feed interface mutated from Chainlink AggregatorV3Interface
 * @author Term Structure Labs
 * @notice Use the customized price feed interface to normalize price feed interface for TermMax Protocol
 */
interface ITermMaxPriceFeed is AggregatorV3Interface {
    function description() external view returns (string memory);
    function asset() external view returns (address);
}
