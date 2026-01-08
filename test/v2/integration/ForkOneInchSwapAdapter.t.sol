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
import {OneInchSwapAdapter, IOneInchRouter} from "contracts/v2/router/swapAdapters/OneInchSwapAdapter.sol";
import {console} from "forge-std/console.sol";

contract ForkOneInchSwapAdapter is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address oneInchRouter = 0x111111125421cA6dc452d289314280a0f8842A65;
    address sender = 0x78f87371Ce25c021cf4953528cAa18C78393Ebbd;

    address constant tokenIn = 0x60bE1e1fE41c1370ADaF5d8e66f07Cf1C2Df2268;
    address constant tokenOut = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    uint256 blockNumber = 24073987;

    bytes data =
        hex"0000000000000000000000000000000000000002410001050000c900004e00a0744c8c0960be1e1fe41c1370adaf5d8e66f07cf1c2df2268cd6b980029e6e6e0733ac8ec3e02be9410d0979900000000000000000000000000000000000000000000000086a7706a995a2fce0c2060be1e1fe41c1370adaf5d8e66f07cf1c2df226845b6ffb13e5206dafe2cc8780e4ddc0e324962656ae4071198002dc6c045b6ffb13e5206dafe2cc8780e4ddc0e324962650000000000000000000000000000000000000000000000000004949cd530d02d60be1e1fe41c1370adaf5d8e66f07cf1c2df22684101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d000000000000000000000000000000000000000000000000000000000000000041729995855c00494d039ab6792f18e368e530dff9310084f196187f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000000000000000000000000d1b71758e21960000137e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400065a8177fae27000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003a50e9000000000000000000000000111111125421ca6dc452d289314280a0f8842a65";

    TermMaxRouterV2 router;
    OneInchSwapAdapter swapAdapter;

    IOneInchRouter.SwapDescription desc;
    bytes swapData;

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        vm.rollFork(blockNumber);
        swapAdapter = new OneInchSwapAdapter(oneInchRouter);
        vm.label(address(swapAdapter), "OneInchSwapAdapter");
        vm.label(tokenIn, "tokenIn");
        vm.label(tokenOut, "tokenOut");
        address admin = vm.randomAddress();

        vm.startPrank(admin);
        IWhitelistManager whitelistManager;
        (router, whitelistManager) = deployRouter(admin);
        router.setWhitelistManager(address(whitelistManager));

        address[] memory adapters = new address[](1);
        adapters[0] = address(swapAdapter);
        whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);
        vm.stopPrank();

        desc = IOneInchRouter.SwapDescription({
            srcToken: tokenIn,
            dstToken: tokenOut,
            srcReceiver: payable(0x60bE1e1fE41c1370ADaF5d8e66f07Cf1C2Df2268),
            dstReceiver: payable(sender),
            amount: 3881139010133876716386,
            minReturnAmount: 2821801,
            flags: 0
        });
        address executor = 0x990636EcB3ff04d33d92E970d3D588bf5cd8E086;

        swapData = abi.encode(executor, desc, data);
    }

    function testSwapExactInToken() public {
        vm.startPrank(sender);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(swapAdapter), tokenIn: tokenIn, tokenOut: tokenOut, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] =
            SwapPath({units: swapUnits, recipient: sender, inputAmount: desc.amount, useBalanceOnchain: false});

        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(sender);
        uint256 tokenOutBalanceBefore = IERC20(tokenOut).balanceOf(sender);

        IERC20(tokenIn).approve(address(router), desc.amount);
        router.swapTokens(swapPaths);

        uint256 tokenInBalanceAfter = IERC20(tokenIn).balanceOf(sender);
        uint256 tokenOutBalanceAfter = IERC20(tokenOut).balanceOf(sender);
        assertGe(tokenOutBalanceAfter - tokenOutBalanceBefore, desc.minReturnAmount);
        assertEq(tokenInBalanceBefore - tokenInBalanceAfter, desc.amount);
        console.log("token out", tokenOutBalanceAfter - tokenOutBalanceBefore);
        console.log("token in", tokenInBalanceBefore - tokenInBalanceAfter);
    }
}
