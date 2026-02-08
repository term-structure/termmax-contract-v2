// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {ITermMaxPriceFeed, AggregatorV3Interface} from "../../priceFeeds/ITermMaxPriceFeed.sol";
import {ISyntheticSharesOracle} from "../../../extensions/ondo/ISyntheticSharesOracle.sol";

/**
 * @title TermMaxOndoPriceFeedAdapter
 * @notice Adapter that wraps Ondo's SyntheticSharesOracle to provide Chainlink AggregatorV3Interface
 * @dev Converts Ondo's getSValue() to Chainlink's latestRoundData() format
 *      The sValue represents the synthetic shares multiplier with 18 decimals
 */
contract TermMaxOndoPriceFeedAdapter is ITermMaxPriceFeed {
    using SafeCast for *;

    error GetRoundDataNotSupported();
    error OraclePaused();

    ISyntheticSharesOracle public immutable ondoOracle;
    address public immutable override asset;

    /**
     * @notice Construct the Ondo price feed adapter
     * @param _ondoOracle The Ondo SyntheticSharesOracle contract address
     * @param _asset The GM asset address to query sValue for
     */
    constructor(address _ondoOracle, address _asset) {
        ondoOracle = ISyntheticSharesOracle(_ondoOracle);
        asset = _asset;
    }

    /**
     * @notice Returns 18 decimals as sValue is denominated in 18 decimals
     */
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Returns description of the adapter
     */
    function description() external view override returns (string memory) {
        return string(abi.encodePacked(IERC20Metadata(asset).symbol(), "/USD"));
    }

    /**
     * @notice Returns version 1
     */
    function version() external pure override returns (uint256) {
        return 1;
    }

    /**
     * @notice Not supported - Ondo oracle doesn't support historical round data
     */
    function getRoundData(uint80 /* _roundId */ )
        external
        pure
        override
        returns (
            uint80, /* roundId */
            int256, /* answer */
            uint256, /* startedAt */
            uint256, /* updatedAt */
            uint80 /* answeredInRound */
        )
    {
        revert GetRoundDataNotSupported();
    }

    /**
     * @notice Get the latest sValue data from Ondo oracle
     * @return roundId Always 1 (not supported by Ondo oracle)
     * @return answer The sValue (synthetic shares multiplier) with 18 decimals
     * @return startedAt The last update timestamp from Ondo oracle
     * @return updatedAt The last update timestamp from Ondo oracle
     * @return answeredInRound Always 1 (not supported by Ondo oracle)
     * @dev Reverts if the oracle is paused for corporate action
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // Get all data from Ondo oracle
        (uint128 sValue,, uint256 lastUpdate, uint256 pauseStartTime,,) = ondoOracle.assetData(asset);

        // Check if oracle is paused for corporate action
        bool isPaused = pauseStartTime > 0 && block.timestamp >= pauseStartTime;
        if (isPaused) {
            revert OraclePaused();
        }

        answer = uint256(sValue).toInt256();

        // Use lastUpdate from oracle as timestamps
        startedAt = lastUpdate;
        updatedAt = lastUpdate;

        return (1, answer, startedAt, updatedAt, 1);
    }
}
