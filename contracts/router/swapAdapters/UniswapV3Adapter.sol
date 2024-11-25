// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./ERC20OutputAdapter.sol";

import {console} from "forge-std/Script.sol";

contract UniswapV3Adapter is ERC20OutputAdapter {
    ISwapRouter public immutable router;

    // ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    constructor(address router_) {
        router = ISwapRouter(router_);
    }

    function swap(
        address tokenIn,
        address,
        bytes memory tokenInData,
        bytes memory swapData
    ) external override returns (bytes memory tokenOutData) {
        uint amount = _decodeAmount(tokenInData);
        IERC20(tokenIn).approve(address(router), amount);
        console.log("trade amount", amount);
        console.log("balance before", IERC20(tokenIn).balanceOf(address(this)));
        (bytes memory path, uint256 amountOutMinimum) = abi.decode(
            swapData,
            (bytes, uint256)
        );
        uint amountOut = router.exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: amountOutMinimum
            })
        );
        console.log("balance after", IERC20(tokenIn).balanceOf(address(this)));
        return _encodeAmount(amountOut);
    }
}
