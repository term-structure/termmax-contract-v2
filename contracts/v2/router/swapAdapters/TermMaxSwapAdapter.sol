// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC20SwapAdapterV2, IERC20} from "./ERC20SwapAdapterV2.sol";
import {ITermMaxOrder} from "contracts/interfaces/ITermMaxOrder.sol";
import {TransferUtilsV2} from "../../lib/TransferUtilsV2.sol";
import {Constants} from "../../../v1/lib/Constants.sol";

struct TermMaxSwapData {
    bool swapExactTokenForToken;
    uint32 scalingFactor; //default is 1e8
    address[] orders;
    uint128[] tradingAmts;
    uint128 netTokenAmt;
    uint256 deadline;
}

contract TermMaxSwapAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using SafeCast for uint256;

    error OrdersAndAmtsLengthNotMatch();

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 netTokenOutOrIn)
    {
        TermMaxSwapData memory data = abi.decode(swapData, (TermMaxSwapData));
        if (data.orders.length != data.tradingAmts.length) revert OrdersAndAmtsLengthNotMatch();
        if (data.swapExactTokenForToken) {
            _scaleTradingAmts(tokenInAmt, data);
            for (uint256 i = 0; i < data.orders.length; ++i) {
                address order = data.orders[i];
                tokenIn.forceApprove(order, data.tradingAmts[i]);
                netTokenOutOrIn += ITermMaxOrder(order).swapExactTokenToToken(
                    tokenIn, tokenOut, recipient, data.tradingAmts[i], 0, data.deadline
                );
            }
            if (netTokenOutOrIn < data.netTokenAmt) revert LessThanMinTokenOut(netTokenOutOrIn, data.netTokenAmt);
        } else {
            /// @dev Token inputs may not be costed totally in this case.
            for (uint256 i = 0; i < data.orders.length; ++i) {
                address order = data.orders[i];
                tokenIn.forceApprove(order, data.netTokenAmt);
                netTokenOutOrIn += ITermMaxOrder(order).swapTokenToExactToken(
                    tokenIn, tokenOut, recipient, data.tradingAmts[i], data.netTokenAmt, data.deadline
                );
            }
            if (netTokenOutOrIn > data.netTokenAmt) revert LessThanMinTokenOut(netTokenOutOrIn, data.netTokenAmt);
        }
    }

    function _scaleTradingAmts(uint256 tokenInAmt, TermMaxSwapData memory data) internal pure virtual {
        uint256 totalTradingAmt;
        for (uint256 i = 0; i < data.tradingAmts.length; ++i) {
            totalTradingAmt += data.tradingAmts[i];
        }
        if (totalTradingAmt == tokenInAmt) {
            // No scaling needed
            return;
        }
        uint256 exceedAmt = tokenInAmt - totalTradingAmt;
        data.tradingAmts[0] += exceedAmt.toUint128();
        // Scale the trading amounts proportionally
        if (data.scalingFactor != 0) {
            uint256 scalingOutAmount = (uint256(data.netTokenAmt) * tokenInAmt / totalTradingAmt) - data.netTokenAmt;
            data.netTokenAmt += (scalingOutAmount * data.scalingFactor / Constants.DECIMAL_BASE).toUint128();
        }
    }
}
