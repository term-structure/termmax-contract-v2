// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;


import {console} from "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {ITermMaxMarket} from "../core/ITermMaxMarket.sol";
import {ITermMaxRouter, ContextCallbackType, SwapInput, LeverageFromTokenData, FlashRepayFromCollData} from "./ITermMaxRouter.sol";
import {MathLib} from "../core/lib/MathLib.sol";
import {IMintableERC20} from "../core/tokens/IMintableERC20.sol";
import {MarketConfig} from "../core/storage/TermMaxStorage.sol";
import {Constants} from "../core/lib/Constants.sol";
import {IFlashLoanReceiver} from "../core/IFlashLoanReceiver.sol";
import {IFlashRepayer} from "../core/tokens/IFlashRepayer.sol";
import {IGearingToken} from "../core/tokens/IGearingToken.sol";

import {
    createTokenInputSimple,
    createTokenOutputSimple,
    createDefaultApproxParams,
    createEmptyLimitOrderData
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";

import {
    IPActionSwapPTV3
} from "@pendle/core-v2/contracts/interfaces/IPActionSwapPTV3.sol";

interface IUniswapV3Router {
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external returns (uint256 amountOut);

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
}

enum SwapType {
    UNISWAP_V3,
    PENDLE
}

struct TermMaxSwapItem {
    SwapType swapType;
    address swapRouter;
    bytes swapData;
    address tokenIn;
    uint256 tokenInAmt;
    address tokenOut;
    uint256 minTokenOutAmt;
}

struct TermMaxSwapData {
    TermMaxSwapItem[] swaps;
    address initTokenIn;
    uint256 initTokenInAmt;
    address finalTokenOut;
    uint256 minFinalTokenOut;
}

struct UniSwapInput {
    address receiver;
    address router;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
}

struct PendleSwapInput {
    address receiver;
    address router;
    address market;
    address tokenIn;
    uint256 tokenInAmt;
    uint256 minTokenOutAmt;
}

contract TermMaxSwapper {
    using Address for address;
    using MathLib for uint256;
    using SafeERC20 for IERC20;

    constructor() {}

    // Ex. USDC -- UniswapV3 -> sUSDe -- Pendle -> PT-sUSDe
    function executeSwaps(
        address sender,
        address receiver,
        TermMaxSwapData calldata swapData
    ) external returns (uint256) {
        TermMaxSwapItem[] memory swaps = swapData.swaps;
        IERC20(swapData.initTokenIn).safeTransferFrom(sender, address(this), swapData.initTokenInAmt);

        for(uint256 i = 0; i < swaps.length; i++) {
            _executeSwap(swaps[i]);
        }

        uint256 tokenOutAmt = IERC20(swapData.finalTokenOut).balanceOf(address(this));
        if(tokenOutAmt < swapData.minFinalTokenOut) {
            revert("TermMaxSwapper: insufficient token out amount");
        }
        IERC20(swapData.finalTokenOut).safeTransfer(receiver, tokenOutAmt);

        return tokenOutAmt;
    }

    function _executeSwap(
        TermMaxSwapItem memory swap
    ) internal {
        if(swap.swapType == SwapType.UNISWAP_V3) {
            // uniswap
            UniSwapInput memory input = abi.decode(swap.swapData, (UniSwapInput));
            doUniswapV3(input);
        } else if(swap.swapType == SwapType.PENDLE) {
            // pendle
            PendleSwapInput memory input = abi.decode(swap.swapData, (PendleSwapInput));
            pendleSimpleSwap(input);
        }
    }

    /** 3rd DEX */
    function doUniswapV3(
        UniSwapInput memory input
    ) internal returns (uint256) {
        IERC20(input.tokenIn).approve(input.router, input.amountIn);
        uint256 amountOut = IUniswapV3Router(input.router).exactInputSingle(
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: input.tokenIn,
                tokenOut: input.tokenOut,
                fee: input.fee,
                recipient: input.recipient, // TODO: assert: address(this)
                deadline: input.deadline,
                amountIn: input.amountIn,
                amountOutMinimum: input.amountOutMinimum,
                sqrtPriceLimitX96: input.sqrtPriceLimitX96
            })
        );

        return amountOut;
    }

    function pendleSimpleSwap(
        PendleSwapInput memory input
    ) internal returns (uint256) {
        IERC20(input.tokenIn).approve(input.router, input.tokenInAmt);
        (uint256 netPtOut,,) = IPActionSwapPTV3(input.router).swapExactTokenForPt(
            address(this),
            input.market,
            input.minTokenOutAmt,
            createDefaultApproxParams(),
            createTokenInputSimple(input.tokenIn, input.tokenInAmt),
            createEmptyLimitOrderData()
        );

        return netPtOut;
    }
}