// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./ERC20SwapAdapterV2.sol";

interface IPancakeRouter {
    // Executes encoded commands along with provided inputs. Reverts if deadline has expired.
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline);
}

/**
 * @title TermMax PancakeUniversalAdapter
 * @author Term Structure Labs
 */
contract PancakeUniversalAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    // BNB Mainnet PancakeSwap Router
    // 0xd9C500DfF816a1Da21A48A732d3498Bf09dc9AEB

    function _swap(address recipient, IERC20 tokenIn, IERC20, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (
            address router,
            bytes memory data,
            bool isExactOut,
            uint256 tradeAmount,
            uint256 netAmount,
            address refundAddress
        ) = abi.decode(swapData, (ISwapRouter, bytes, bool, uint256, uint256, uint256, address));
        // tradeAmount check
        if (!isExactOut && tradeAmount != amount) {
            revert("PancakeUniversalAdapter: tradeAmount must equal amount for exactIn swap");
        }
        // maxTokenIn check
        if (isExactOut && netAmount > amount) {
            revert("PancakeUniversalAdapter: netAmount must be less than or equal to amount for exactOut swap");
        }
        (bool success, bytes memory returnData) = router.call{value: 0}(data);
        if (!success) {
            revert("PancakeUniversalAdapter: swap failed");
        }
        tokenOutAmt = abi.decode(returnData, (uint256));
    }
}
