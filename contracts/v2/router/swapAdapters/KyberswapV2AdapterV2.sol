// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import "./ERC20SwapAdapterV2.sol";

interface IKyberScalingHelper {
    function getScaledInputData(bytes calldata inputData, uint256 newAmount)
        external
        view
        returns (bool isSuccess, bytes memory data);
}

/**
 * @title TermMax KyberswapV2AdapterV2
 * @author Term Structure Labs
 */
contract KyberswapV2AdapterV2 is ERC20SwapAdapterV2 {
    using Address for address;
    using TransferUtilsV2 for IERC20;

    error KyberScalingFailed();

    address public immutable router;
    address public immutable KYBER_SCALING_HELPER;

    constructor(address router_, address scalingHelper_) {
        router = router_;
        KYBER_SCALING_HELPER = scalingHelper_; // 0x2f577A41BeC1BE1152AeEA12e73b7391d15f655D
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20, uint256 amountIn, bytes memory swapData)
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
