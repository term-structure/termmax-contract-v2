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
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {StrataVaultAdapter} from "contracts/v2/router/swapAdapters/StrataVaultAdapter.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {console} from "forge-std/console.sol";

contract ForkStrataVaultAdapter is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address srUSDE = 0x3d7d6fdf07EE548B939A80edbc9B2256d0cdc003;
    address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address susde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    TermMaxRouterV2 router;
    StrataVaultAdapter strataAdapter;

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        strataAdapter = new StrataVaultAdapter();
        vm.label(address(strataAdapter), "StrataVaultAdapter");
        vm.label(usdc, "USDC");
        vm.label(srUSDE, "srUSDE");
        vm.label(usde, "USDE");
        vm.label(susde, "sUSDE");
        address admin = vm.randomAddress();

        vm.startPrank(admin);
        IWhitelistManager whitelistManager;
        (router, whitelistManager) = deployRouter(admin);
        router.setWhitelistManager(address(whitelistManager));

        address[] memory adapters = new address[](1);
        adapters[0] = address(strataAdapter);
        whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);
        vm.stopPrank();
    }

    function testDepositSrUSDe() public {
        address user = vm.addr(1);
        vm.label(user, "user");
        uint256 amount = 10000 * 10 ** IERC20Metadata(usde).decimals();
        deal(usde, user, amount);
        vm.startPrank(user);
        IERC20(usde).approve(address(router), amount);
        uint256 mintTokenOut = IERC4626(srUSDE).previewDeposit(amount);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(strataAdapter),
            tokenIn: usde,
            tokenOut: srUSDE,
            swapData: abi.encode(ERC4626VaultAdapterV2.Action.Deposit, amount, mintTokenOut)
        });
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: amount, useBalanceOnchain: false});

        uint256 srUSDeBefore = IERC20(srUSDE).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 srUSDeAfter = IERC20(srUSDE).balanceOf(user);
        console.log("srUSDe out", srUSDeAfter - srUSDeBefore);
    }

    function testRedeemSrUSDe() public {
        address user = vm.addr(1);
        vm.label(user, "user");
        uint256 amount = 10000 * 10 ** IERC20Metadata(srUSDE).decimals();
        deal(srUSDE, user, amount);
        vm.startPrank(user);
        IERC20(srUSDE).approve(address(router), amount);
        uint256 redeemTokenOut = IERC4626(srUSDE).previewRedeem(amount);
        // change to sUSDe
        // deduct 1 to avoid rounding issue
        redeemTokenOut = IERC4626(susde).previewDeposit(redeemTokenOut) - 1;
        console.log("Expected sUSDe out", redeemTokenOut);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(strataAdapter),
            tokenIn: srUSDE,
            tokenOut: susde,
            swapData: abi.encode(ERC4626VaultAdapterV2.Action.Redeem, amount, redeemTokenOut)
        });
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: amount, useBalanceOnchain: false});

        uint256 susdeBefore = IERC20(susde).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 susdeAfter = IERC20(susde).balanceOf(user);
        console.log("susde out", susdeAfter - susdeBefore);
    }
}
