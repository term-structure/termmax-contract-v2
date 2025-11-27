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
import {PancakeSmartAdapter} from "contracts/v2/router/swapAdapters/PancakeSmartAdapter.sol";
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {console} from "forge-std/console.sol";

contract ForkPancakeSmartAdapter is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant pancakeSmartRouter = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;

    TermMaxRouterV2 router;
    PancakeSmartAdapter pancakeSmartAdapter;
    address admin = vm.addr(1);

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        pancakeSmartAdapter = new PancakeSmartAdapter();
        vm.label(address(pancakeSmartAdapter), "PancakeSmartAdapter");
        vm.label(pancakeSmartRouter, "pancakeSmartRouter");
        vm.label(WBNB, "WBNB");
        vm.label(USDT, "USDT");

        vm.startPrank(admin);
        IWhitelistManager whitelistManager;
        (router, whitelistManager) = deployRouter(admin);
        router.setWhitelistManager(address(whitelistManager));
        console.log("router", address(router));
        console.log("whitelistManager", address(whitelistManager));

        address[] memory adapters = new address[](1);
        adapters[0] = address(pancakeSmartAdapter);
        whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);
        vm.stopPrank();
    }

    function testSwapExactIn() public {
        console.log("Start testSwapExactIn");
        uint256 blockNumber = 69618252;
        vm.roll(blockNumber);
        address user = vm.addr(2);
        vm.deal(user, 1 ether);
        address tokenIn = WBNB;
        address tokenOut = USDT;
        uint256 inputAmount = 10e18;
        deal(tokenIn, user, inputAmount);
        uint256 netOutAmt = 1000e18;
        bytes memory data =
            hex"ac9650d8000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000000e404e45aaf000000000000000000000000bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c00000000000000000000000055d398326f99059ff775485246999027b31979550000000000000000000000000000000000000000000000000000000000000064000000000000000000000000c7183455a4c133ae270771860664b6b7ec320bb10000000000000000000000000000000000000000000000006124fee993bc000000000000000000000000000000000000000000000000001edfa1d5bd0309b82e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000124b858183f00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000080000000000000000000000000c7183455a4c133ae270771860664b6b7ec320bb100000000000000000000000000000000000000000000000029a2241af62c000000000000000000000000000000000000000000000000000d3a90f2525c769fed0000000000000000000000000000000000000000000000000000000000000042bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c0001f48d0d000ee44948fc98c9b98a4fa4921476f08b0d00006455d398326f99059ff775485246999027b319795500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bool isExactOut = false;
        bytes memory swapData = abi.encode(pancakeSmartRouter, data, isExactOut, inputAmount, netOutAmt, user);
        vm.startPrank(user);
        IERC20(tokenIn).approve(address(router), inputAmount);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(pancakeSmartAdapter), tokenIn: tokenIn, tokenOut: tokenOut, swapData: swapData});
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: inputAmount, useBalanceOnchain: false});

        uint256 tokenInBefore = IERC20(tokenIn).balanceOf(user);
        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 tokenInAfter = IERC20(tokenIn).balanceOf(user);
        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(user);
        assertEq(tokenInBefore - tokenInAfter, inputAmount);
        assertGe(tokenOutAfter - tokenOutBefore, netOutAmt);
        console.log("token out", tokenOutAfter - tokenOutBefore);
    }
}
