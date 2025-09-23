// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./ERC20SwapAdapterV2.sol";
import {ITermMaxOrder} from "contracts/interfaces/ITermMaxOrder.sol";
import {TransferUtilsV2} from "../../lib/TransferUtilsV2.sol";
import {Constants} from "../../../v1/lib/Constants.sol";
import {ArrayUtilsV2} from "../../lib/ArrayUtilsV2.sol";
import {IWhitelistManager} from "../../access/IWhitelistManager.sol";

/// @notice The data structure for the TermMax swap adapter.
struct TermMaxSwapData {
    /// @notice Whether the swap is exact token in for net token out.
    bool swapExactTokenForToken;
    /// @notice The scaling factor for the trading amounts.
    /// @dev Decimals is 8.
    uint32 scalingFactor;
    /// @notice The orders to be traded.
    address[] orders;
    /// @notice The trading amounts for each order.
    uint128[] tradingAmts;
    /// @notice The net token amount to check actual output.
    uint128 netTokenAmt;
    /// @notice The deadline for the swap.
    uint256 deadline;
}

contract TermMaxSwapAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;
    using ArrayUtilsV2 for uint256[];
    using ArrayUtilsV2 for uint128[];

    /// @notice Emitted when the orders and trading amounts length do not match.
    error OrdersAndAmtsLengthNotMatch();
    /// @notice Emitted when the actual token cost or income is not as expected.
    error ActualTokenBalanceNotMatch();
    /// @notice Emitted when the callback is not authorized.
    error UnauthorizedCallback(address callback);
    /// @notice Emitted when the pool is not authorized.
    error UnauthorizedPool(address pool);

    IWhitelistManager public immutable whitelistManager;

    constructor(address _whitelistManager) {
        whitelistManager = IWhitelistManager(_whitelistManager);
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 netTokenOutOrIn)
    {
        TermMaxSwapData memory data = abi.decode(swapData, (TermMaxSwapData));
        if (data.orders.length != data.tradingAmts.length) revert OrdersAndAmtsLengthNotMatch();

        uint256 inputTokenBalanceBefore = tokenIn.balanceOf(address(this));
        uint256 outputTokenBalanceBefore = tokenOut.balanceOf(recipient);
        uint256 finalInput;
        uint256 finalOutput;
        if (data.swapExactTokenForToken) {
            _scaleTradingAmts(tokenInAmt, data);
            for (uint256 i = 0; i < data.orders.length; ++i) {
                address order = data.orders[i];
                _checkOrderCallback(order);
                tokenIn.safeIncreaseAllowance(order, data.tradingAmts[i]);
                netTokenOutOrIn += ITermMaxOrder(order).swapExactTokenToToken(
                    tokenIn, tokenOut, recipient, data.tradingAmts[i], 0, data.deadline
                );
            }
            if (netTokenOutOrIn < data.netTokenAmt) {
                revert LessThanMinTokenOut(netTokenOutOrIn, data.netTokenAmt);
            }
            finalInput = tokenInAmt;
            finalOutput = netTokenOutOrIn;
        } else {
            for (uint256 i = 0; i < data.orders.length; ++i) {
                address order = data.orders[i];
                _checkOrderCallback(order);
                // Use maximum allowance for the swap because the final input amount is unknown
                tokenIn.safeIncreaseAllowance(order, data.netTokenAmt);
                netTokenOutOrIn += ITermMaxOrder(order).swapTokenToExactToken(
                    tokenIn, tokenOut, recipient, data.tradingAmts[i], data.netTokenAmt, data.deadline
                );
            }
            if (netTokenOutOrIn > data.netTokenAmt) {
                revert ExceedMaxTokenIn(netTokenOutOrIn, data.netTokenAmt);
            }
            finalInput = netTokenOutOrIn;
            finalOutput = data.tradingAmts.sum();
        }
        uint256 actualInput = inputTokenBalanceBefore - tokenIn.balanceOf(address(this));
        uint256 actualOutput = tokenOut.balanceOf(recipient) - outputTokenBalanceBefore;
        if (actualInput != finalInput || actualOutput != finalOutput) {
            revert ActualTokenBalanceNotMatch();
        }
    }

    function _checkOrderCallback(address order) internal view virtual {
        address callbackAddr = address(ITermMaxOrder(order).orderConfig().swapTrigger);
        address pool = address(ITermMaxOrder(order).pool());
        if (
            callbackAddr != address(0)
                && !whitelistManager.isWhitelisted(callbackAddr, IWhitelistManager.ContractModule.ORDER_CALLBACK)
        ) {
            revert UnauthorizedCallback(callbackAddr);
        }
        if (pool != address(0) && !whitelistManager.isWhitelisted(pool, IWhitelistManager.ContractModule.POOL)) {
            revert UnauthorizedPool(pool);
        }
    }

    function _scaleTradingAmts(uint256 tokenInAmt, TermMaxSwapData memory data) internal pure virtual {
        uint256 totalTradingAmt = data.tradingAmts.sum();
        if (totalTradingAmt == tokenInAmt) {
            // No scaling needed
            return;
        }
        uint256 exceedAmt = tokenInAmt - totalTradingAmt;
        data.tradingAmts[0] += exceedAmt.toUint128();
        // Scale the trading amounts proportionally
        if (data.scalingFactor != 0) {
            uint256 scalingOutAmount =
                (uint256(data.netTokenAmt).mulDiv(tokenInAmt, totalTradingAmt, Math.Rounding.Ceil) - data.netTokenAmt);
            data.netTokenAmt += (scalingOutAmount.mulDiv(data.scalingFactor, Constants.DECIMAL_BASE)).toUint128();
        }
    }
}
