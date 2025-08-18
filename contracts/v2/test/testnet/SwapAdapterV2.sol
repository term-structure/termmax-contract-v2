// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IMintableERC20} from "../../../v1/tokens/IMintableERC20.sol";
import "../../router/swapAdapters/ERC20SwapAdapterV2.sol";
import {MockPriceFeed} from "../../../v1/test/MockPriceFeed.sol";

contract SwapAdapterV2 is ERC20SwapAdapterV2 {
    address public immutable pool;

    constructor(address pool_) {
        pool = pool_;
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (address tokenInPriceFeedAddr, address tokenOutPriceFeedAddr) = abi.decode(swapData, (address, address));

        uint8 tokenInDecimals = IERC20Metadata(address(tokenIn)).decimals();
        uint8 tokenOutDecimals = IERC20Metadata(address(tokenOut)).decimals();

        MockPriceFeed tokenInPriceFeed = MockPriceFeed(tokenInPriceFeedAddr);
        MockPriceFeed tokenOutPriceFeed = MockPriceFeed(address(tokenOutPriceFeedAddr));
        (, int256 tokenInPrice,,,) = tokenInPriceFeed.latestRoundData();
        uint8 tokenInPriceDecimals = tokenInPriceFeed.decimals();
        (, int256 tokenOutPrice,,,) = tokenOutPriceFeed.latestRoundData();
        uint8 tokenOutPriceDecimals = tokenOutPriceFeed.decimals();

        tokenOutAmt = (amount * uint256(tokenInPrice) * 10 ** tokenOutPriceDecimals * 10 ** tokenOutDecimals)
            / (uint256(tokenOutPrice) * 10 ** tokenInPriceDecimals * 10 ** tokenInDecimals);
        IERC20(tokenIn).transfer(pool, amount);
        IMintableERC20(address(tokenOut)).mint(recipient, tokenOutAmt);
    }
}
