// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./TermMaxUniswapTWAPPriceFeed.sol";
import {IPancakeSwapV3Pool} from "../../extensions/pancake/IPancakeSwapV3Pool.sol";

contract TermMaxPancakeTWAPPriceFeed is TermMaxUniswapTWAPPriceFeed {
    constructor(address _pool, uint32 _twapPeriod, address _baseToken, address _quoteToken)
        TermMaxUniswapTWAPPriceFeed(_pool, _twapPeriod, _baseToken, _quoteToken)
    {}

    function _ensureSufficientObservations(address _pool, uint32 _twapPeriod) internal view virtual override {
        (,, uint16 observationIndex, uint16 observationCardinality,,,) = IPancakeSwapV3Pool(_pool).slot0();
        if (observationCardinality <= 1) revert InsufficientObservationCardinality();
        uint16 oldestIndex = uint16((uint256(observationIndex) + 1) % observationCardinality);
        (uint32 oldestTimestamp,,, bool oldestInitialized) = IUniswapV3Pool(_pool).observations(oldestIndex);
        uint256 currentTimestamp = block.timestamp;

        if (!oldestInitialized) {
            (uint32 latestTimestamp,,, bool latestInitialized) = IUniswapV3Pool(_pool).observations(observationIndex);
            if (!latestInitialized) revert InsufficientObservationHistory();
            if (currentTimestamp - uint256(latestTimestamp) < _twapPeriod) revert InsufficientObservationHistory();
            return;
        }

        if (oldestTimestamp == 0) revert InsufficientObservationHistory();
        if (currentTimestamp - uint256(oldestTimestamp) < _twapPeriod) revert InsufficientObservationHistory();
    }
}
