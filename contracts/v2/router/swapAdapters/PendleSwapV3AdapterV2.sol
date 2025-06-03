// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../v1/router/swapAdapters/PendleSwapV3Adapter.sol";

/**
 * @title TermMax PendleSwapV3Adapter
 * @author Term Structure Labs
 */
contract PendleSwapV3AdapterV2 is PendleSwapV3Adapter {
    using TransferUtils for IERC20;

    constructor(address router_) PendleSwapV3Adapter(router_) {}

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
        IERC20(tokenIn).safeIncreaseAllowance(address(router), amount);

        /**
         * Note: Scaling Input/Output amount
         */
        minTokenOut = (minTokenOut * amount) / inAmount;
        if (tokenOut == PT) {
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
                (tokenOutAmt,) = router.redeemPyToToken(
                    address(this), PT.YT(), amount, createTokenOutputStruct(address(tokenOut), minTokenOut)
                );
            } else {
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
