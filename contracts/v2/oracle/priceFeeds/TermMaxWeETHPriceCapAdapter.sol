// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPriceCapAdapter} from "contracts/v2/extensions/aave/IPriceCapAdapter.sol";
/**
 * @title TermMaxWeETHPriceCapAdapter
 * @notice Adapter that wraps Aave's WeETHPriceCapAdapter to provide Chainlink-like interface
 * @dev Converts Aave's latestAnswer() to Chainlink's latestRoundData() format
 */

contract TermMaxWeETHPriceCapAdapter {
    IPriceCapAdapter public immutable adapter;
    uint8 private immutable _decimals;

    constructor(address _aaveWeETHPriceCapAdapter) {
        adapter = IPriceCapAdapter(_aaveWeETHPriceCapAdapter);
        _decimals = adapter.decimals();
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        answer = adapter.latestAnswer();
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external view returns (string memory) {
        return adapter.description();
    }
}
