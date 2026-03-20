// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20SwapAdapterV2.sol";

/**
 * @title TermMax LifiSwapAdapter
 * @notice This adapter enables swaps via the LiFi router.
 * @author Term Structure Labs
 */
contract LifiSwapAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;

    error InvalidTradeAmount();

    address public immutable router;

    constructor(address _lifiRouter) {
        router = _lifiRouter;
    }

    function _isSelectorWhitelisted(bytes4 selector) internal pure override returns (bool) {
        //swapTokensGeneric (0x4630a0d8)
        //swapTokensMultipleV3ERC20ToERC20 (0x5fd9ae2e)
        //swapTokensSingleV3ERC20ToERC20 (0x4666fc80)
        return selector == 0x4630a0d8 || selector == 0x5fd9ae2e || selector == 0x4666fc80;
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (bytes memory data, uint256 tradeAmount, uint256 netAmount, address refundAddress) =
            abi.decode(swapData, (bytes, uint256, uint256, address));
        _validateSelector(data);
        if (tradeAmount < amount) {
            _refund(refundAddress, tokenIn, amount - tradeAmount);
        } else if (tradeAmount > amount) {
            revert InvalidTradeAmount();
        }
        ///@dev make sure the recipient in swapdata is this contract
        uint256 tokenOutBalBefore = tokenOut.balanceOf(address(this));
        tokenIn.safeApprove(address(router), tradeAmount);

        (bool success, bytes memory returnData) = router.call{value: 0}(data);
        if (!success) {
            assembly {
                let ptr := add(returnData, 0x20)
                let len := mload(returnData)
                revert(ptr, len)
            }
        }
        tokenOutAmt = tokenOut.balanceOf(address(this)) - tokenOutBalBefore;

        if (tokenOutAmt < netAmount) revert LessThanMinTokenOut(tokenOutAmt, netAmount);
        if (recipient != address(this)) {
            tokenOut.safeTransfer(recipient, tokenOutAmt);
        }
    }
}
