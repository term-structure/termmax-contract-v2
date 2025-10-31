// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface ISparkLinearOracle is AggregatorV3Interface {
    function PT() external view returns (address);
    function maturity() external view returns (uint256);
    function getDiscount(uint256 timeLeft) external view returns (uint256);
}
