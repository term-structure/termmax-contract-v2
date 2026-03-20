// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {SwapUnit, ITermMaxRouter, TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {
    IGearingToken,
    GearingTokenEvents,
    AbstractGearingToken,
    GtConfig
} from "contracts/v1/tokens/AbstractGearingToken.sol";
import {PendleSwapV3AdapterV2} from "contracts/v2/router/swapAdapters/PendleSwapV3AdapterV2.sol";
import {OdosV2AdapterV2} from "contracts/v2/router/swapAdapters/OdosV2AdapterV2.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {
    ForkBaseTestV2,
    TermMaxFactoryV2,
    MarketConfig,
    IERC20,
    MarketInitialParams,
    IERC20Metadata
} from "../mainnet-fork/ForkBaseTestV2.sol";
import {ITermMaxMarketV2} from "contracts/v2/ITermMaxMarketV2.sol";
import {
    ITermMaxRouterV2,
    TermMaxRouterV2,
    SwapPath,
    FlashRepayOptions,
    RouterErrors
} from "contracts/v2/router/TermMaxRouterV2.sol";
import {IWhitelistManager} from "contracts/v2/access/IWhitelistManager.sol";
import {LifiSwapAdapter, ERC20SwapAdapterV2} from "contracts/v2/router/swapAdapters/LifiSwapAdapter.sol";
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {console} from "forge-std/console.sol";

contract ForkLifiSwapAdapter is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address constant tokenIn = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant tokenOut = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 tradeAmt = 1000000;
    uint256 netAmt = 601581707;
    address constant lifiRouter = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;

    TermMaxRouterV2 router = TermMaxRouterV2(0x324596C1682a5675008f6e58F9C4E0A894b079c7);
    LifiSwapAdapter lifiSwapAdapter;
    IWhitelistManager whitelistManager = IWhitelistManager(0xB84f2a39b271D92586c61232a73ee1F7adFBf317);

    address admin;

    uint256 blockNumber = 24633422;

    bytes swapData =
        hex"5fd9ae2e5b27fc87afdeb62f7d451bd6df0874071216bb4c8cb04730a6ca28a8297a0a9400000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000324596c1682a5675008f6e58f9c4e0a894b079c7000000000000000000000000000000000000000000000000000000002522a41d000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000000086c6966692d617069000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a307830303030303030303030303030303030303030303030303030303030303030303030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000003ef238c36035880efbdfa239d218186b79ad1d6f0000000000000000000000003ef238c36035880efbdfa239d218186b79ad1d6f0000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c59900000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000084eedd56e10000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009c4000000000000000000000000b9c0de368bece5e76b52545a8e377a4c118f597b00000000000000000000000000000000000000000000000000000000000000000000000000000000ac4c6e212a361c968f1725b4d055b47e63f80b75000000000000000000000000ac4c6e212a361c968f1725b4d055b47e63f80b750000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000f387c00000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003a45f3bd1c80000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c59900000000000000000000000000000000000000000000000000000000000f387c0000000000000000000000001231deb6f5749ef6ce6943a275a1d3e7486f4eae000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000002519226a000000000000000000000000c10ee9031f2a0b84766a86b55a8d90f357910fb400000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000284ba3f2165000000000000000000000000de7259893af7cdbc9fd806c6ba61d22d581d566700000000000000000000000000000000000000000000000000000000000981b30000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c59900000000000000000000000000000000000000000000000000000000000f387c000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000002942ef3d0000000000000000000000001231deb6f5749ef6ce6943a275a1d3e7486f4eae000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000011c019cdc49910b0002012260fac5e5542a773aa44fbcfedf7c193bc2c59901ffff05000000000000000000000000000000000000000000000000000000000000003ff5f5b97624542d72a9e06f04804bf81baa15e2b4020100c10ee9031f2a0b84766a86b55a8d90f357910fb4dac17f958d2ee523a2206206994597c13d831ec7f38804a5090e01dac17f958d2ee523a2206206994597c13d831ec701ffff06000000000004444c5dc75cb358380d2e3de08a90a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000800000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c10ee9031f2a0b84766a86b55a8d90f357910fb4a5090ea50c0e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        vm.roll(blockNumber);

        lifiSwapAdapter = new LifiSwapAdapter(lifiRouter);
        vm.label(address(lifiSwapAdapter), "LifiSwapAdapter");
        vm.label(lifiRouter, "lifiRouter");
        vm.label(tokenIn, "tokenIn");
        vm.label(tokenOut, "tokenOut");

        admin = router.owner();
        vm.startPrank(admin);
        console.log("router", address(router));
        console.log("whitelistManager", address(whitelistManager));

        address[] memory adapters = new address[](1);
        adapters[0] = address(lifiSwapAdapter);
        whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);
        vm.stopPrank();
    }

    function testSwap() public {
        console.log("Start testSwap");
        address user = vm.addr(2);
        deal(tokenIn, user, tradeAmt);

        bytes memory swapData = abi.encode(swapData, tradeAmt, netAmt, user);
        vm.startPrank(user);
        IERC20(tokenIn).approve(address(router), tradeAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(lifiSwapAdapter), tokenIn: tokenIn, tokenOut: tokenOut, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: tradeAmt, useBalanceOnchain: false});

        uint256 tokenInBefore = IERC20(tokenIn).balanceOf(user);
        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 tokenInAfter = IERC20(tokenIn).balanceOf(user);
        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(user);
        assertEq(tokenInBefore - tokenInAfter, tradeAmt);
        assertGe(tokenOutAfter - tokenOutBefore, netAmt);
        console.log("token out", tokenOutAfter - tokenOutBefore);
    }

    function testRefund() public {
        console.log("Start testRefund");
        address user = vm.addr(2);
        uint256 refundAmt = 1000;
        tradeAmt;
        deal(tokenIn, user, tradeAmt + refundAmt);

        bytes memory swapData = abi.encode(swapData, tradeAmt, netAmt, user);
        vm.startPrank(user);
        IERC20(tokenIn).approve(address(router), tradeAmt + refundAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(lifiSwapAdapter), tokenIn: tokenIn, tokenOut: tokenOut, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] =
            SwapPath({units: swapUnits, recipient: user, inputAmount: tradeAmt + refundAmt, useBalanceOnchain: false});

        uint256 tokenInBefore = IERC20(tokenIn).balanceOf(user);
        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 tokenInAfter = IERC20(tokenIn).balanceOf(user);
        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(user);
        assertEq(tokenInAfter, refundAmt);
        assertEq(tokenInBefore - tokenInAfter, tradeAmt);
        assertGe(tokenOutAfter - tokenOutBefore, netAmt);
        console.log("token out", tokenOutAfter - tokenOutBefore);
    }

    function testInvalidTradeAmount() public {
        console.log("Start testInvalidTradeAmount");
        address user = vm.addr(2);
        uint256 invalidTradeAmt = tradeAmt - 1000;
        deal(tokenIn, user, invalidTradeAmt);

        bytes memory swapData = abi.encode(swapData, tradeAmt, netAmt, user);
        vm.startPrank(user);
        IERC20(tokenIn).approve(address(router), invalidTradeAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(lifiSwapAdapter), tokenIn: tokenIn, tokenOut: tokenOut, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] =
            SwapPath({units: swapUnits, recipient: user, inputAmount: invalidTradeAmt, useBalanceOnchain: false});

        bytes memory errorData = abi.encodeWithSelector(LifiSwapAdapter.InvalidTradeAmount.selector);
        vm.expectRevert(abi.encodeWithSelector(RouterErrors.SwapFailed.selector, address(lifiSwapAdapter), errorData));
        router.swapTokens(swapPaths);
    }

    function testInvalidSelector() public {
        address user = vm.addr(2);
        uint256 invalidTradeAmt = tradeAmt - 1000;
        deal(tokenIn, user, invalidTradeAmt);
        swapData[0] = 0x00; // invalid selector
        bytes memory data = swapData;
        bytes4 invalidSelector;
        assembly {
            invalidSelector := mload(add(data, 0x20))
        }
        bytes memory swapData = abi.encode(swapData, tradeAmt, netAmt, user);
        vm.startPrank(user);
        IERC20(tokenIn).approve(address(router), invalidTradeAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(lifiSwapAdapter), tokenIn: tokenIn, tokenOut: tokenOut, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] =
            SwapPath({units: swapUnits, recipient: user, inputAmount: invalidTradeAmt, useBalanceOnchain: false});
        bytes memory errorData =
            abi.encodeWithSelector(ERC20SwapAdapterV2.SelectorNotWhitelisted.selector, invalidSelector);
        vm.expectRevert(abi.encodeWithSelector(RouterErrors.SwapFailed.selector, address(lifiSwapAdapter), errorData));
        router.swapTokens(swapPaths);
    }
}
