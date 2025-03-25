// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PendleHelper} from "../../extensions/PendleHelper.sol";
import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IPMarket, IPPrincipalToken, IPYieldToken} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import "./ERC20SwapAdapter.sol";
/**
 * @title TermMax PendleSwapV3Adapter
 * @author Term Structure Labs
 */

contract PendleSwapV3Adapter is ERC20SwapAdapter, PendleHelper {
    IPAllActionV3 public immutable router;

    constructor(address router_) {
        router = IPAllActionV3(router_);
    }

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (address ptMarketAddr, uint256 inAmount, uint256 minTokenOut) =
            abi.decode(swapData, (address, uint256, uint256));
        IPMarket market = IPMarket(ptMarketAddr);

        (, IPPrincipalToken PT,) = market.readTokens();
        IERC20(tokenIn).approve(address(router), amount);

        /**
         * Note: Scaling Input/Output amount
         */
        minTokenOut = (minTokenOut * amount) / inAmount;

        if (tokenOut == PT) {
            IERC20(tokenIn).approve(address(router), amount);
            (tokenOutAmt,,) = router.swapExactTokenForPt(
                address(this),
                address(market),
                minTokenOut,
                defaultApprox,
                createTokenInputStruct(address(tokenIn), amount),
                emptyLimit
            );
        } else {
            if (PT.isExpired()) {
                IPYieldToken YT = IPYieldToken(PT.YT());
                IERC20(tokenIn).transfer(address(YT), amount);
                tokenOutAmt = IPYieldToken(YT).redeemPY(address(this));
                if (tokenOutAmt < minTokenOut) {
                    revert LessThanMinTokenOut(tokenOutAmt, minTokenOut);
                }
            } else {
                IERC20(tokenIn).approve(address(router), amount);
                (tokenOutAmt,,) = router.swapExactPtForToken(
                    address(this),
                    address(market),
                    amount,
                    createTokenOutputStruct(address(tokenOut), minTokenOut),
                    emptyLimit
                );
            }
        }
    }
}
