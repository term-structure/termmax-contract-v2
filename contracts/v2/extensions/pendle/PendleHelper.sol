// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";

abstract contract PendleHelper {
    // EmptySwap means no swap aggregator is involved
    SwapData public emptySwap;

    // EmptyLimit means no limit order is involved
    LimitOrderData public emptyLimit;

    // DefaultApprox means no off-chain preparation is involved, more gas consuming (~ 180k gas)
    ApproxParams public defaultApprox = ApproxParams(0, type(uint256).max, 0, 256, 1e14);

    /// @notice create a simple TokenInput struct without using any aggregators. For more info please refer to
    /// IPAllActionTypeV3.sol
    function createTokenInputStruct(address tokenIn, uint256 netTokenIn)
        internal
        pure
        returns (TokenInput memory input)
    {
        input.tokenIn = tokenIn;
        input.netTokenIn = netTokenIn;
        input.tokenMintSy = tokenIn;
    }

    /// @notice create a simple TokenOutput struct without using any aggregators. For more info please refer to
    /// IPAllActionTypeV3.sol
    function createTokenOutputStruct(address tokenOut, uint256 minTokenOut)
        internal
        pure
        returns (TokenOutput memory output)
    {
        output.tokenOut = tokenOut;
        output.minTokenOut = minTokenOut;
        output.tokenRedeemSy = tokenOut;
    }
}
