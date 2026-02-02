// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGMTokenManager} from "contracts/v2/extensions/ondo/IGMTokenManager.sol";
import "./ERC20SwapAdapterV2.sol";

/**
 * @title TermMax OndoSwapAdapter
 * @notice This adapter enables swaps stocks via OndoFinance Market.
 *         Make sure to use exact output amounts without scaling because OndoFinance Market doesn't support it.
 * @author Term Structure Labs
 */
contract OndoSwapAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    IGMTokenManager public immutable ondoMarket;
    IERC20 public immutable USDon;

    constructor(address _ondoMarket) {
        ondoMarket = IGMTokenManager(_ondoMarket);
        USDon = IERC20(IGMTokenManager(_ondoMarket).usdon());
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (uint256 netAmt, address refundAddress, IGMTokenManager.Quote memory quote, bytes memory signature) =
            abi.decode(swapData, (uint256, address, IGMTokenManager.Quote, bytes));

        (uint256 amountIn, uint256 expectAmt) =
            quote.side == IGMTokenManager.QuoteSide.BUY ? (netAmt, quote.quantity) : (quote.quantity, netAmt);
        ///@dev make sure the recipient in swapdata is this contract
        tokenIn.safeApprove(address(ondoMarket), amountIn);
        uint256 tokenInBalBefore = tokenIn.balanceOf(address(this));
        uint256 tokenOutBalBefore = tokenOut.balanceOf(address(this));
        uint256 usdonBalanceBefore;
        if (quote.side == IGMTokenManager.QuoteSide.BUY) {
            usdonBalanceBefore = USDon.balanceOf(address(this));
            ondoMarket.mintWithAttestation(quote, signature, address(tokenIn), amountIn);
        } else {
            ondoMarket.redeemWithAttestation(quote, signature, address(tokenOut), expectAmt);
        }
        uint256 realCost = tokenInBalBefore - tokenIn.balanceOf(address(this));
        // calculate output amount because OndoMarket ouput amount is base ondo USD
        tokenOutAmt = tokenOut.balanceOf(address(this)) - tokenOutBalBefore;
        // refund excess input tokens
        if (refundAddress != address(0) && refundAddress != address(this)) {
            if (amount > realCost) {
                tokenIn.safeTransfer(refundAddress, amount - realCost);
            }
            // refund USDon if any(ondo market always use USDon as refund token)
            if (
                quote.side == IGMTokenManager.QuoteSide.BUY && address(tokenIn) != address(USDon)
                    && address(tokenOut) != address(USDon)
            ) {
                uint256 usdonBalanceAfter = USDon.balanceOf(address(this));
                if (usdonBalanceAfter > usdonBalanceBefore) {
                    USDon.safeTransfer(refundAddress, usdonBalanceAfter - usdonBalanceBefore);
                }
            }
        }
        // transfer output tokens to recipient if needed
        if (recipient != address(this)) {
            tokenOut.safeTransfer(recipient, tokenOutAmt);
        }
    }
}
