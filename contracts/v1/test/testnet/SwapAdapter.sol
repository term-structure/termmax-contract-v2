// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {IMintableERC20, IERC20} from "../../tokens/IMintableERC20.sol";
import "../../router/swapAdapters/ERC20SwapAdapter.sol";
import {MockPriceFeed} from "../../test/MockPriceFeed.sol";

contract SwapAdapter is ERC20SwapAdapter {
    address public immutable pool;

    constructor(address pool_) {
        pool = pool_;
    }

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (address tokenInPriceFeedAddr, address tokenOutPriceFeedAddr) = abi.decode(swapData, (address, address));

        uint8 tokenInDecimals = IMintableERC20(address(tokenIn)).decimals();
        uint8 tokenOutDecimals = IMintableERC20(address(tokenOut)).decimals();

        MockPriceFeed tokenInPriceFeed = MockPriceFeed(tokenInPriceFeedAddr);
        MockPriceFeed tokenOutPriceFeed = MockPriceFeed(address(tokenOutPriceFeedAddr));
        (, int256 tokenInPrice,,,) = tokenInPriceFeed.latestRoundData();
        uint8 tokenInPriceDecimals = tokenInPriceFeed.decimals();
        (, int256 tokenOutPrice,,,) = tokenOutPriceFeed.latestRoundData();
        uint8 tokenOutPriceDecimals = tokenOutPriceFeed.decimals();

        tokenOutAmt = (amount * uint256(tokenInPrice) * 10 ** tokenOutPriceDecimals * 10 ** tokenOutDecimals)
            / (uint256(tokenOutPrice) * 10 ** tokenInPriceDecimals * 10 ** tokenInDecimals);
        console.log("tokenInAmt: %d", amount);
        console.log("tokenOutAmt: %d", tokenOutAmt);
        IERC20(tokenIn).transfer(pool, amount);
        IMintableERC20(address(tokenOut)).mint(address(this), tokenOutAmt);
    }
}
