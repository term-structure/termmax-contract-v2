// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20SwapAdapterV2, IERC20} from "./ERC20SwapAdapterV2.sol";
import {ITermMaxOrder} from "contracts/interfaces/ITermMaxOrder.sol";
import {TransferUtilsV2} from "../../lib/TransferUtilsV2.sol";

struct TermMaxSwapData {
    bool swapExactTokenForToken;
    address tokenIn;
    address tokenOut;
    address[] orders;
    uint128[] tradingAmts;
    uint128 netTokenAmt;
    uint256 deadline;
}

contract TermMaxSwapAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;

    error OrdersAndAmtsLengthNotMatch();

    function _swap(address receipient, IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 netTokenOutOrIn)
    {
        TermMaxSwapData memory data = abi.decode(swapData, (TermMaxSwapData));
        if (data.orders.length != data.tradingAmts.length) revert OrdersAndAmtsLengthNotMatch();

        if (data.swapExactTokenForToken) {
            for (uint256 i = 0; i < data.orders.length; ++i) {
                address order = data.orders[i];
                tokenIn.forceApprove(order, data.netTokenAmt);
                netTokenOutOrIn += ITermMaxOrder(order).swapExactTokenToToken(
                    tokenIn, tokenOut, receipient, data.tradingAmts[i], 0, data.deadline
                );
            }
            if (netTokenOutOrIn < data.netTokenAmt) revert LessThanMinTokenOut(netTokenOutOrIn, data.netTokenAmt);
        } else {
            for (uint256 i = 0; i < data.orders.length; ++i) {
                address order = data.orders[i];
                tokenIn.forceApprove(order, data.netTokenAmt);
                netTokenOutOrIn += ITermMaxOrder(order).swapTokenToExactToken(
                    tokenIn, tokenOut, receipient, data.tradingAmts[i], data.netTokenAmt, data.deadline
                );
            }
            if (netTokenOutOrIn > data.netTokenAmt) revert LessThanMinTokenOut(netTokenOutOrIn, data.netTokenAmt);
        }
    }
}
