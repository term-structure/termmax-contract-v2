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
import {ITermMaxRouterV2, TermMaxRouterV2, SwapPath, FlashRepayOptions} from "contracts/v2/router/TermMaxRouterV2.sol";
import {IWhitelistManager} from "contracts/v2/access/IWhitelistManager.sol";
import {UniswapV3AdapterV2} from "contracts/v2/router/swapAdapters/UniswapV3AdapterV2.sol";
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {console} from "forge-std/console.sol";

contract ForkUniswapAdapterV2 is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint24 fee = 500;

    TermMaxRouterV2 router;
    UniswapV3AdapterV2 uniswapAdapter;

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        uniswapAdapter = new UniswapV3AdapterV2();
        vm.label(address(uniswapAdapter), "UniswapV3AdapterV2");
        vm.label(uniswapRouter, "uniswapRouter");
        vm.label(uniswapFactory, "uniswapFactory");
        vm.label(WBTC, "WBTC");
        vm.label(USDC, "USDC");
        address admin = vm.randomAddress();

        vm.startPrank(admin);
        IWhitelistManager whitelistManager;
        (router, whitelistManager) = deployRouter(admin);
        router.setWhitelistManager(address(whitelistManager));

        address[] memory adapters = new address[](1);
        adapters[0] = address(uniswapAdapter);
        whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);
        vm.stopPrank();
    }

    function testSwapExactOutToken() public {
        address user = vm.addr(1);
        vm.label(user, "user");
        uint256 btcAmt = 1e8;
        deal(WBTC, user, btcAmt);
        vm.startPrank(user);
        IERC20(WBTC).approve(address(router), btcAmt);
        uint256 wantToBuyUSDC = 2000e6;

        uint256 maxTokenIn = btcAmt / 10; // max 0.1 WBTC
        bytes memory swapData = abi.encode(
            uniswapRouter,
            abi.encodePacked(USDC, fee, WBTC), // path
            true, // isExactOut
            block.timestamp + 1 hours, // deadline
            wantToBuyUSDC, // tradeAmount, will be scaled
            maxTokenIn, // max amountIn
            user // refundAddress
        );

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({adapter: address(uniswapAdapter), tokenIn: WBTC, tokenOut: USDC, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: btcAmt, useBalanceOnchain: false});

        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        uint256 btcBefore = IERC20(WBTC).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        uint256 btcAfter = IERC20(WBTC).balanceOf(user);
        assertEq(usdcAfter - usdcBefore, wantToBuyUSDC);
        assertLe(btcBefore - btcAfter, maxTokenIn);
        console.log("usdc out", usdcAfter - usdcBefore);
        console.log("btc in", btcBefore - btcAfter);
    }

    function testSwapExactInToken() public {
        address user = vm.addr(1);
        vm.label(user, "user");
        uint256 btcAmt = 1e8;
        deal(WBTC, user, btcAmt);
        vm.startPrank(user);
        IERC20(WBTC).approve(address(router), btcAmt);
        uint256 wantToSellWBTC = btcAmt / 10; // sell 0.1 WBTC

        uint256 minUSDCOut = 1500e6;
        bytes memory swapData = abi.encode(
            uniswapRouter,
            abi.encodePacked(WBTC, fee, USDC), // path
            false, // isExactOut
            block.timestamp + 1 hours, // deadline
            wantToSellWBTC, // tradeAmount, will be scaled
            minUSDCOut, // netAmount
            address(0) // refundAddress
        );

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({adapter: address(uniswapAdapter), tokenIn: WBTC, tokenOut: USDC, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] =
            SwapPath({units: swapUnits, recipient: user, inputAmount: wantToSellWBTC, useBalanceOnchain: false});

        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        uint256 btcBefore = IERC20(WBTC).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        uint256 btcAfter = IERC20(WBTC).balanceOf(user);
        assertGe(usdcAfter - usdcBefore, minUSDCOut);
        assertEq(btcBefore - btcAfter, wantToSellWBTC);
        console.log("usdc out", usdcAfter - usdcBefore);
        console.log("btc in", btcBefore - btcAfter);
    }
}
