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
import {OndoSwapAdapter, IGMTokenManager} from "contracts/v2/router/swapAdapters/OndoSwapAdapter.sol";
import {console} from "forge-std/console.sol";
import {AccessManagerV2} from "contracts/v2/access/AccessManagerV2.sol";

contract ForkOndoSwapAdapter is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address ondoMarket = 0x2c158BC456e027b2AfFCCadF1BDBD9f5fC4c5C8c;

    address stableAsset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address stockAsset = 0xf6b1117ec07684D3958caD8BEb1b302bfD21103f;

    address deployer = 0x56E3665038C5F0b56Cc7D81aC66C86521274B251;
    address accessManager = 0xDA4aAF85Bb924B53DCc2DFFa9e1A9C2Ef97aCFDF;
    address whitelistManager = 0xB84f2a39b271D92586c61232a73ee1F7adFBf317;
    TermMaxRouterV2 router = TermMaxRouterV2(0x324596C1682a5675008f6e58F9C4E0A894b079c7);
    OndoSwapAdapter ondoSwapAdapter;

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function _initRouter(uint256 blockNumber) internal {
        vm.rollFork(blockNumber);
        ondoSwapAdapter = new OndoSwapAdapter(ondoMarket);
        vm.label(address(ondoSwapAdapter), "OndoSwapAdapter");
        vm.label(stableAsset, "stableAsset");
        vm.label(stockAsset, "stockAsset");

        vm.startPrank(deployer);

        address[] memory adapters = new address[](1);
        adapters[0] = address(ondoSwapAdapter);

        AccessManagerV2(accessManager).batchSetWhitelist(
            IWhitelistManager(whitelistManager), adapters, IWhitelistManager.ContractModule.ADAPTER, true
        );
        vm.stopPrank();
    }

    function testBuyStock() public {
        _initRouter(24288335);
        address user = vm.addr(1);
        vm.label(user, "user");
        address tokenIn = stableAsset;
        address tokenOut = stockAsset;

        IGMTokenManager.Quote memory quote = IGMTokenManager.Quote({
            chainId: 1,
            attestationId: 179224311159881551208014097287582743993,
            userId: 0x474d0000000000002aed7722fd56fe1500000000000000000000000000000000,
            asset: stockAsset,
            price: 433746765000000000000,
            quantity: 3000000000000000000,
            expiration: 1769060975,
            side: IGMTokenManager.QuoteSide.BUY,
            additionalData: bytes32(0)
        });
        // tokenIn value to USDC with 6 decimals
        uint256 maxTokenInAmt = quote.quantity * quote.price / 1e18 * 1e6 / 1e18;
        console.log("maxTokenInAmt", maxTokenInAmt);
        bytes memory signature =
            hex"490a61be83354210137df50a299745908f053e9b1170c643670fe3d6df38846b3c26a8319dbf399c7dfadde4a5589712e2168fe6fb0f7c3b1c3178b6518146761c";
        bytes memory swapData = abi.encode(maxTokenInAmt, user, quote, signature);

        vm.startPrank(user);
        // 1500 USDC
        deal(tokenIn, user, maxTokenInAmt);
        IERC20(tokenIn).approve(address(router), maxTokenInAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(ondoSwapAdapter), tokenIn: tokenIn, tokenOut: tokenOut, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] =
            SwapPath({units: swapUnits, recipient: user, inputAmount: maxTokenInAmt, useBalanceOnchain: false});

        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(user);
        uint256 tokenInBefore = IERC20(tokenIn).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(user);
        uint256 tokenInAfter = IERC20(tokenIn).balanceOf(user);
        assertGe(tokenOutAfter - tokenOutBefore, quote.quantity);
        assertLe(tokenInBefore - tokenInAfter, maxTokenInAmt);
        console.log("tokenOut out", tokenOutAfter - tokenOutBefore);
        console.log("tokenIn in", tokenInBefore - tokenInAfter);
    }

    function testSellStock() public {
        _initRouter(24288672);
        address user = vm.addr(2);
        vm.label(user, "user2");
        address tokenIn = stockAsset;
        address tokenOut = stableAsset;

        IGMTokenManager.Quote memory quote = IGMTokenManager.Quote({
            chainId: 1,
            attestationId: 229466323641516910638038585072769334048,
            userId: 0x474d0000000000002aed7722fd56fe1500000000000000000000000000000000,
            asset: stockAsset,
            price: 433223280000000000000,
            quantity: 3000000000000000000,
            expiration: 1769064958,
            side: IGMTokenManager.QuoteSide.SELL,
            additionalData: bytes32(0)
        });
        uint256 tokenInAmt = quote.quantity;
        // expected output amount in USDC with 6 decimals
        uint256 expectedTokenOutAmt = tokenInAmt * quote.price / 1e18 * 1e6 / 1e18; // 1% slippage
        console.log("expectedTokenOutAmt", expectedTokenOutAmt);
        bytes memory signature =
            hex"e568c7f688af1d2472e2c066673ba94249dcb4d3805bee7a2e2b5989c5cf2f8519be0ba39de8a371e660c7b1b972a8f80219af287ec200dc3f75d7830a1fe9ba1c";
        bytes memory swapData = abi.encode(expectedTokenOutAmt, user, quote, signature);
        vm.startPrank(user);
        // 3 Ondo TSLA
        deal(tokenIn, user, tokenInAmt);
        IERC20(tokenIn).approve(address(router), tokenInAmt);
        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(ondoSwapAdapter), tokenIn: tokenIn, tokenOut: tokenOut, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: tokenInAmt, useBalanceOnchain: false});
        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(user);
        uint256 tokenInBefore = IERC20(tokenIn).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(user);
        uint256 tokenInAfter = IERC20(tokenIn).balanceOf(user);
        assertGe(tokenOutAfter - tokenOutBefore, expectedTokenOutAmt);
        assertLe(tokenInBefore - tokenInAfter, tokenInAmt);
        console.log("tokenOut out", tokenOutAfter - tokenOutBefore);
        console.log("tokenIn in", tokenInBefore - tokenInAfter);
        vm.stopPrank();
    }
}
