// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20SwapAdapterV2.sol";

/**
 * @title OdosRouterV2 interface
 */
interface IOdosRouterV2 {
    /// @notice Struct to hold swap token information
    struct SwapTokenInfo {
        address inputToken;
        uint256 inputAmount;
        address inputReceiver;
        address outputToken;
        uint256 outputQuote;
        uint256 outputMin;
        address outputReceiver;
    }

    function swap(SwapTokenInfo memory tokenInfo, bytes calldata pathDefinition, address executor, uint32 referralCode)
        external
        payable
        returns (uint256 amountOut);
}

/**
 * @title TermMax OdosAdapterV2AdapterV2
 * @author Term Structure Labs
 */
contract OdosV2AdapterV2 is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    IOdosRouterV2 public immutable router;

    constructor(address router_) {
        router = IOdosRouterV2(router_);
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20, uint256 amountIn, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        tokenIn.safeApprove(address(router), amountIn);

        (
            IOdosRouterV2.SwapTokenInfo memory tokenInfo,
            bytes memory pathDefinition,
            address executor,
            uint32 referralCode
        ) = abi.decode(swapData, (IOdosRouterV2.SwapTokenInfo, bytes, address, uint32));

        /**
         * Note: Scaling Input/Output amount
         */
        tokenInfo.outputQuote = tokenInfo.outputQuote.mulDiv(amountIn, tokenInfo.inputAmount, Math.Rounding.Ceil);
        tokenInfo.outputMin = tokenInfo.outputMin.mulDiv(amountIn, tokenInfo.inputAmount, Math.Rounding.Ceil);
        tokenInfo.inputAmount = amountIn;
        tokenInfo.outputReceiver = recipient;

        tokenOutAmt = router.swap(tokenInfo, pathDefinition, executor, referralCode);
    }
}
