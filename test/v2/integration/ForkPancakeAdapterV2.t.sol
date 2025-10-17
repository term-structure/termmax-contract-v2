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

contract ForkPancakeAdapterV2 is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address pancakeFactory = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant pancakeRouter = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;
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
        vm.label(pancakeRouter, "pancakeRouter");
        vm.label(pancakeFactory, "pancakeFactory");
        vm.label(WBNB, "WBNB");
        vm.label(USDT, "USDT");
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
        uint256 wbnbAmt = 1e18;
        deal(WBNB, user, wbnbAmt);
        vm.startPrank(user);
        IERC20(WBNB).approve(address(router), wbnbAmt);
        uint256 wantToBuyUSDT = 20e18;

        uint256 maxTokenIn = wbnbAmt / 10; // max 0.1 WBNB
        bytes memory swapData = abi.encode(
            pancakeRouter,
            abi.encodePacked(USDT, fee, WBNB), // path
            true, // isExactOut
            block.timestamp + 1 hours, // deadline
            wantToBuyUSDT, // tradeAmount, will be scaled
            maxTokenIn, // max amountIn
            user // refundAddress
        );

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({adapter: address(uniswapAdapter), tokenIn: WBNB, tokenOut: USDT, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: wbnbAmt, useBalanceOnchain: false});

        uint256 usdtBefore = IERC20(USDT).balanceOf(user);
        uint256 wbnbBefore = IERC20(WBNB).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 usdtAfter = IERC20(USDT).balanceOf(user);
        uint256 wbnbAfter = IERC20(WBNB).balanceOf(user);
        assertEq(usdtAfter - usdtBefore, wantToBuyUSDT);
        assertLe(wbnbBefore - wbnbAfter, maxTokenIn);
        console.log("usdt out", usdtAfter - usdtBefore);
        console.log("wbnb in", wbnbBefore - wbnbAfter);
    }

    function testSwapExactInToken() public {
        address user = vm.addr(1);
        vm.label(user, "user");
        uint256 wbnbAmt = 1e18;
        deal(WBNB, user, wbnbAmt);
        vm.startPrank(user);
        IERC20(WBNB).approve(address(router), wbnbAmt);
        uint256 wantToSellWBNB = wbnbAmt / 10; // sell 0.1 WBNB

        uint256 minUSDTOut = 15e18;
        bytes memory swapData = abi.encode(
            pancakeRouter,
            abi.encodePacked(WBNB, fee, USDT), // path
            false, // isExactOut
            block.timestamp + 1 hours, // deadline
            wantToSellWBNB, // tradeAmount, will be scaled
            minUSDTOut, // netAmount
            address(0) // refundAddress
        );

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({adapter: address(uniswapAdapter), tokenIn: WBNB, tokenOut: USDT, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] =
            SwapPath({units: swapUnits, recipient: user, inputAmount: wantToSellWBNB, useBalanceOnchain: false});

        uint256 usdtBefore = IERC20(USDT).balanceOf(user);
        uint256 wbnbBefore = IERC20(WBNB).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 usdtAfter = IERC20(USDT).balanceOf(user);
        uint256 wbnbAfter = IERC20(WBNB).balanceOf(user);
        assertGe(usdtAfter - usdtBefore, minUSDTOut);
        assertEq(wbnbBefore - wbnbAfter, wantToSellWBNB);
        console.log("usdt out", usdtAfter - usdtBefore);
        console.log("wbnb in", wbnbBefore - wbnbAfter);
    }
}
