// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IPMarket, IPPrincipalToken, IPYieldToken} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import {PendleHelper} from "../../extensions/pendle/PendleHelper.sol";
import "./ERC20SwapAdapterV2.sol";

/**
 * @title TermMax PendleSwapV3AdapterV2
 * @author Term Structure Labs
 */
contract PendleSwapV3AdapterV2 is ERC20SwapAdapterV2, PendleHelper {
    using TransferUtilsV2 for IERC20;

    IPAllActionV3 public immutable router;

    constructor(address router_) {
        router = IPAllActionV3(router_);
    }

    function _swap(address receipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        onlyProxy
        returns (uint256 tokenOutAmt)
    {
        (address ptMarketAddr, uint256 inAmount, uint256 minTokenOut) =
            abi.decode(swapData, (address, uint256, uint256));
        IPMarket market = IPMarket(ptMarketAddr);

        (, IPPrincipalToken PT,) = market.readTokens();
        IERC20(tokenIn).safeIncreaseAllowance(address(router), amount);

        /**
         * Note: Scaling Input/Output amount
         */
        minTokenOut = (minTokenOut * amount + inAmount - 1) / inAmount;
        if (tokenOut == PT) {
            (tokenOutAmt,,) = router.swapExactTokenForPt(
                receipient,
                address(market),
                minTokenOut,
                defaultApprox,
                createTokenInputStruct(address(tokenIn), amount),
                emptyLimit
            );
        } else {
            if (PT.isExpired()) {
                (tokenOutAmt,) = router.redeemPyToToken(
                    receipient, PT.YT(), amount, createTokenOutputStruct(address(tokenOut), minTokenOut)
                );
            } else {
                (tokenOutAmt,,) = router.swapExactPtForToken(
                    receipient,
                    address(market),
                    amount,
                    createTokenOutputStruct(address(tokenOut), minTokenOut),
                    emptyLimit
                );
            }
        }
    }
}
