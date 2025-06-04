// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PendlePYLpOracle} from "@pendle/core-v2/contracts/oracles/PtYtLpOracle/PendlePYLpOracle.sol";
import {PendlePYOracleLib} from "@pendle/core-v2/contracts/oracles/PtYtLpOracle/PendlePYOracleLib.sol";
import {PMath} from "@pendle/core-v2/contracts/core/libraries/math/PMath.sol";
import {IPMarket} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title The customized Pendle PT price feed contract mutated from Chainlink AggregatorV3Interface
 * @author Term Structure Labs
 * @notice Use the customized price feed contract to normalized price feed interface for TermMax Protocol
 */
contract PTWithPriceFeed is AggregatorV3Interface {
    using Math for uint256;
    using SafeCast for *;
    using PendlePYOracleLib for IPMarket;

    // Pendle PY LP oracle, refer to `https://docs.pendle.finance/Developers/Oracles/HowToIntegratePtAndLpOracle`
    PendlePYLpOracle public immutable PY_LP_ORACLE;
    // Pendle market
    IPMarket public immutable MARKET;
    // TWAP duration
    uint32 public immutable DURATION;
    // Price feed interface
    AggregatorV3Interface public immutable PRICE_FEED;

    // error to call `getRoundData` function
    error GetRoundDataNotSupported();
    // error when Pendle PY LP oracle is not ready
    error OracleIsNotReady();
    // error when price is zero
    error PriceIsZero();

    /**
     * @notice Construct the PT price feed contract
     * @param pendlePYLpOracle The Pendle PY LP oracle contract
     * @param market The Pendle market contract
     * @param duration The TWAP duration
     * @param priceFeed The price feed interface
     */
    constructor(address pendlePYLpOracle, address market, uint32 duration, address priceFeed) {
        (, int256 answer,,,) = AggregatorV3Interface(priceFeed).latestRoundData();
        if (answer == 0) revert PriceIsZero();

        PY_LP_ORACLE = PendlePYLpOracle(pendlePYLpOracle);
        MARKET = IPMarket(market);
        DURATION = duration;
        PRICE_FEED = AggregatorV3Interface(priceFeed);

        if (!_oracleIsReady()) revert OracleIsNotReady();
    }

    /**
     * @notice Revert this function because cannot get the chi (rate accumulator) at a specific round
     */
    function getRoundData(uint80 /* _roundId */ )
        external
        pure
        returns (
            uint80, /* roundId */
            int256, /* answer */
            uint256, /* startedAt */
            uint256, /* updatedAt */
            uint80 /* answeredInRound */
        )
    {
        // error to call this function because cannot get the chi (rate accumulator) at a specific round
        revert GetRoundDataNotSupported();
    }

    /**
     * @notice Get the latest round data from chainlink and calculate the PT price by multiplying PT rate in SY and SY price
     * @return roundId The round ID
     * @return answer The calculated PT price
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound The round ID of the round in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // PT price = PT rate in SY * SY price / PT to asset rate base
        uint256 ptRateInSy = MARKET.getPtToSyRate(DURATION); // PT -> SY

        (roundId, answer, startedAt, updatedAt, answeredInRound) = PRICE_FEED.latestRoundData();
        answer = ptRateInSy.mulDiv(answer.toUint256(), PMath.ONE).toInt256();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /**
     * @notice Check if the Pendle PY LP oracle is ready
     * @return True if the oracle is ready, otherwise false
     */
    function _oracleIsReady() internal view returns (bool) {
        (bool increaseCardinalityRequired,, bool oldestObservationSatisfied) =
            PY_LP_ORACLE.getOracleState(address(MARKET), DURATION);

        return !increaseCardinalityRequired && oldestObservationSatisfied;
    }

    /**
     * ========== Return original price feed data ==========
     */
    function decimals() external view returns (uint8) {
        return PRICE_FEED.decimals();
    }

    function description() external view returns (string memory) {
        return PRICE_FEED.description();
    }

    function version() external view returns (uint256) {
        return PRICE_FEED.version();
    }
}
