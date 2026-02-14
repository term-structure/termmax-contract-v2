// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITermMaxPriceFeed} from "./ITermMaxPriceFeed.sol";
import {VersionV2} from "../../VersionV2.sol";

interface IUSPCPriceFeed {
    // return USPC/USDC price with 36 decimals
    function getLatestPriceInfo() external view returns (uint256 price, uint256 timestamp);
}

/**
 * @title TermMaxUSPCPriceFeedAdapter
 * @notice Adapter that wraps USPC oracle to provide Chainlink AggregatorV3Interface
 */
contract TermMaxUSPCPriceFeedAdapter is ITermMaxPriceFeed, VersionV2 {
    using SafeCast for *;

    error GetRoundDataNotSupported();

    uint8 internal constant USPC_PRICE_DECIMALS = 18;
    uint256 internal constant PRICE_SCALE_DOWN = 1e18;

    IUSPCPriceFeed public immutable uspcOracle;
    address public immutable asset;

    constructor(address _uspcOracle, address _asset) {
        uspcOracle = IUSPCPriceFeed(_uspcOracle);
        asset = _asset;
    }

    function decimals() external pure override returns (uint8) {
        return USPC_PRICE_DECIMALS;
    }

    function description() external view override returns (string memory) {
        string memory symbol = IERC20Metadata(asset).symbol();
        return string(abi.encodePacked("TermMax price feed: ", symbol, "/USDC"));
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

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

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (uint256 price, uint256 timestamp) = uspcOracle.getLatestPriceInfo();
        // source oracle returns 36 decimals, normalize to 18 decimals here
        answer = (price / PRICE_SCALE_DOWN).toInt256();

        // round information is not supported by source oracle
        roundId = 1;
        answeredInRound = 1;

        // use oracle timestamp for compatibility with downstream stale checks
        startedAt = timestamp;
        updatedAt = timestamp;
    }
}
