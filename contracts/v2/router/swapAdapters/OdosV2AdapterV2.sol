// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./ERC20SwapAdapterV2.sol";

interface IOdosRouterV2 {
    struct swapTokenInfo {
        address inputToken;
        uint256 inputAmount;
        address inputReceiver;
        address outputToken;
        uint256 outputQuote;
        uint256 outputMin;
        address outputReceiver;
    }

    function swap(swapTokenInfo memory tokenInfo, bytes calldata pathDefinition, address executor, uint32 referralCode)
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

    error InvalidOutputToken();

    IOdosRouterV2 public immutable router;

    constructor(address router_) {
        router = IOdosRouterV2(router_);
    }

    function _swap(address receipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        tokenIn.safeIncreaseAllowance(address(router), amountIn);

        (
            IOdosRouterV2.swapTokenInfo memory tokenInfo,
            bytes memory pathDefinition,
            address executor,
            uint32 referralCode
        ) = abi.decode(swapData, (IOdosRouterV2.swapTokenInfo, bytes, address, uint32));

        if (tokenInfo.outputToken != address(tokenOut)) {
            revert InvalidOutputToken();
        }
        /**
         * Note: Scaling Input/Output amount
         */
        tokenInfo.outputQuote = (tokenInfo.outputQuote * amountIn) / tokenInfo.inputAmount;
        tokenInfo.outputMin = (tokenInfo.outputMin * amountIn) / tokenInfo.inputAmount;
        tokenInfo.inputAmount = amountIn;
        tokenInfo.outputReceiver = receipient;

        tokenOutAmt = router.swap(tokenInfo, pathDefinition, executor, referralCode);
    }
}
