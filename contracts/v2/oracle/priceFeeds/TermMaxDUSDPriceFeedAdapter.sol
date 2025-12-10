// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ITermMaxPriceFeed, AggregatorV3Interface} from "./ITermMaxPriceFeed.sol";
import {VersionV2} from "../../VersionV2.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IDUSDOracle {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    // return DUSD/USDC price with 18 decimals
    function getSharePrice() external view returns (uint256);
}

/**
 * @title TermMaxDUSDPriceFeedAdapter
 * @notice Adapter that wraps DUSD Oracle to provide Chainlink AggregatorV3Interface
 * @dev Directly returns DUSD Oracle's getSharePrice() without conversion
 */
contract TermMaxDUSDPriceFeedAdapter is ITermMaxPriceFeed, VersionV2 {
    using SafeCast for *;

    error GetRoundDataNotSupported();

    IDUSDOracle public immutable dusdOracle;
    address public immutable asset;

    /**
     * @notice Construct the DUSD price feed adapter
     * @param _dusdOracle The DUSD oracle contract address
     * @param _asset The DUSD asset address
     */
    constructor(address _dusdOracle, address _asset) {
        dusdOracle = IDUSDOracle(_dusdOracle);
        asset = _asset;
    }

    function decimals() external view override returns (uint8) {
        return dusdOracle.decimals();
    }

    function description() external view override returns (string memory) {
        return dusdOracle.description();
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    /**
     * @notice Not supported - DUSD oracle doesn't support historical round data
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
     * @notice Get the latest price data from DUSD oracle
     * @return roundId Always 1 (not supported by DUSD oracle)
     * @return answer The DUSD/USDC price with 18 decimals (as returned by DUSD oracle)
     * @return startedAt Current block timestamp
     * @return updatedAt Current block timestamp
     * @return answeredInRound Always 1 (not supported by DUSD oracle)
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // Get DUSD/USDC price directly from oracle
        uint256 sharePrice = dusdOracle.getSharePrice();
        answer = sharePrice.toInt256();

        // Set timestamps to current block
        startedAt = block.timestamp;
        updatedAt = block.timestamp;

        // roundId and answeredInRound are not supported by DUSD oracle
        roundId = 1;
        answeredInRound = 1;
    }
}
