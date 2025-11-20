// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISparkLinearOracle} from "../../extensions/morpho/ISparkLinearOracle.sol";

/**
 * @title TermMaxSparkLinearOracleAdapter
 * @notice Adapter that wraps PendleSparkLinearOracle to support TermMaxOracleAggregator V1
 * @dev Use the block timestamp for startedAt and updatedAt in latestRoundData()
 */
contract TermMaxSparkLinearOracleAdapter {
    ISparkLinearOracle public immutable adapter;
    uint8 private immutable _decimals;
    string private _description;

    constructor(address _pendleSparkLinearOracle) {
        adapter = ISparkLinearOracle(_pendleSparkLinearOracle);
        _decimals = adapter.decimals();

        string memory ptName = IERC20Metadata(adapter.PT()).symbol();

        _description = string(abi.encodePacked("TermMax Linear Oracle Adapter for ", ptName));
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = adapter.latestRoundData();
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function asset() external view returns (address) {
        return adapter.PT();
    }

    function description() external view returns (string memory) {
        return _description;
    }
}
