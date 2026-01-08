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

    constructor(address _ondoMarket) {
        ondoMarket = IGMTokenManager(_ondoMarket);
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (uint256 amountIn, address refundAddress, IGMTokenManager.Quote memory quote, bytes memory signature) =
            abi.decode(swapData, (uint256, address, IGMTokenManager.Quote, bytes));

        ///@dev make sure the recipient in swapdata is this contract
        tokenIn.safeApprove(address(ondoMarket), amountIn);
        uint256 tokenInBalBefore = tokenIn.balanceOf(address(this));
        uint256 tokenOutBalBefore = tokenOut.balanceOf(address(this));
        if (quote.side == IGMTokenManager.QuoteSide.BUY) {
            ondoMarket.mintWithAttestation(quote, signature, address(tokenIn), amountIn);
        } else {
            ondoMarket.redeemWithAttestation(quote, signature, address(tokenIn), amountIn);
        }
        uint256 realCost = tokenInBalBefore - tokenIn.balanceOf(address(this));
        // calculate output amount because OndoMarket ouput amount is base ondo USD
        tokenOutAmt = tokenOut.balanceOf(address(this)) - tokenOutBalBefore;
        // refund excess input tokens
        if (amount > realCost && refundAddress != address(0) && refundAddress != address(this)) {
            tokenIn.safeTransfer(refundAddress, amount - realCost);
        }
        // transfer output tokens to recipient if needed
        if (recipient != address(this)) {
            tokenOut.safeTransfer(recipient, tokenOutAmt);
        }
    }
}
