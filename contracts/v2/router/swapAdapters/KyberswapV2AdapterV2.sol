// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../v1/router/swapAdapters/KyberswapV2Adapter.sol";

/**
 * @title TermMax KyberswapV2AdapterV2
 * @author Term Structure Labs
 */
contract KyberswapV2AdapterV2 is KyberswapV2Adapter {
    using Address for address;
    using TransferUtils for IERC20;

    error KyberScalingFailed();

    constructor(address router_, address scalingHelper_) KyberswapV2Adapter(router_, scalingHelper_) {}

    function _swap(IERC20 tokenIn, IERC20, uint256 amountIn, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256)
    {
        IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);
        (bool isSuccess, bytes memory newSwapData) =
            IKyberScalingHelper(KYBER_SCALING_HELPER).getScaledInputData(swapData, amountIn);

        require(isSuccess, KyberScalingFailed());

        bytes memory returnData = router.functionCall(newSwapData);
        (uint256 tokenOutAmt,) = abi.decode(returnData, (uint256, uint256));
        return tokenOutAmt;
    }
}
