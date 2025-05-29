// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../v1/router/swapAdapters/OdosV2Adapter.sol";

/**
 * @title TermMax OdosAdapterV2AdapterV2
 * @author Term Structure Labs
 */
contract OdosV2AdapterV2 is OdosV2Adapter {
    using TransferUtils for IERC20;

    error InvalidOutputToken();

    constructor(address router_) OdosV2Adapter(router_) {}

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, bytes memory swapData)
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
        tokenInfo.outputReceiver = address(this);

        tokenOutAmt = router.swap(tokenInfo, pathDefinition, executor, referralCode);
    }
}
