// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "../core/tokens/IMintableERC20.sol";
import "../router/swapAdapters/ERC20OutputAdapter.sol";

contract MockSwapAdapter is ERC20OutputAdapter {
    address public immutable pool;

    constructor(address pool_) {
        pool = pool_;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        bytes memory tokenInData,
        bytes memory swapData
    ) external override returns (bytes memory tokenOutData) {
        uint256 minTokenOut = abi.decode(swapData, (uint256));

        uint amount = _decodeAmount(tokenInData);

        IERC20(tokenIn).transfer(pool, amount);

        uint256 netPtOut = minTokenOut;
        IMintableERC20(tokenOut).mint(address(this), netPtOut);
        return _encodeAmount(netPtOut);
    }
}
