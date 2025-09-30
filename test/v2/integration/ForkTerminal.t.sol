// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
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
import {TerminalVaultAdapter} from "contracts/v2/router/swapAdapters/TerminalVaultAdapter.sol";
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {console} from "forge-std/console.sol";

contract ForkTerminalTest is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address susde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address tusde = 0xA01227A26A7710bc75071286539E47AdB6DEa417;
    address tETH = 0xa1150cd4A014e06F5E0A6ec9453fE0208dA5adAb;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address weEth = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    // only can redeem tUSDE to sUSDE
    address tUSDERedeemVault = 0xFaAE52c6A6d477f859a740a76B29c33559ace18c;
    // only can deposit USDE to get tUSDE
    address tUSDEDepositVault = 0x5AD2e3d65f8eCDc36eeba38BAE3Cc6Ff258D2dfa;
    // only can redeem tETH to weETH
    address tETHRedeemVault = 0xE042678e6c6871Fa279e037C11e390f31334ba0B;
    // only can deposit WETH to get tETH
    address tETHDepositVault = 0xC93bb8D5581D74272F0E304593af9Ab4E3A0181b;

    TermMaxRouterV2 router;
    TerminalVaultAdapter terminalAdapter;

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        terminalAdapter = new TerminalVaultAdapter();
        vm.label(susde, "susde");
        vm.label(tusde, "tusde");
        vm.label(tUSDERedeemVault, "tUSDERedeemVault");
        vm.label(tUSDEDepositVault, "tUSDEDepositVault");
        vm.label(address(terminalAdapter), "terminalAdapter");

        address admin = vm.randomAddress();

        vm.startPrank(admin);
        IWhitelistManager whitelistManager;
        (router, whitelistManager) = deployRouter(admin);
        router.setWhitelistManager(address(whitelistManager));

        address[] memory adapters = new address[](1);
        adapters[0] = address(terminalAdapter);
        whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);
        vm.stopPrank();
    }

    function testRedeemtTUSDE() public {
        address user = vm.addr(1);
        vm.label(user, "user");
        uint256 tusdeAmt = 100_000e18;
        deal(tusde, user, tusdeAmt);
        vm.startPrank(user);
        IERC20(tusde).approve(address(router), tusdeAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(terminalAdapter),
            tokenIn: tusde,
            tokenOut: susde,
            swapData: abi.encode(
                ERC4626VaultAdapterV2.Action.Redeem, tUSDERedeemVault, tusdeAmt, tusdeAmt * 8 / 10, bytes32(0)
            ) // inAmount, minReceiveAmount
        });
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: tusdeAmt, useBalanceOnchain: false});

        uint256 susdeBefore = IERC20(susde).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 susdeAfter = IERC20(susde).balanceOf(user);
        console.log("susde out", susdeAfter - susdeBefore);
    }

    function testDepositTUSDE() public {
        address user = vm.addr(1);
        vm.label(user, "user");
        uint256 usdeAmt = 100_000e18;
        deal(usde, user, usdeAmt);
        vm.startPrank(user);
        IERC20(usde).approve(address(router), usdeAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(terminalAdapter),
            tokenIn: usde,
            tokenOut: tusde,
            swapData: abi.encode(
                ERC4626VaultAdapterV2.Action.Deposit, tUSDEDepositVault, usdeAmt, usdeAmt * 8 / 10, bytes32(0)
            ) // inAmount, minReceiveAmount, referrerId
        });
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: usdeAmt, useBalanceOnchain: false});

        uint256 tusdeBefore = IERC20(tusde).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 tusdeAfter = IERC20(tusde).balanceOf(user);
        console.log("tusde out", tusdeAfter - tusdeBefore);
    }

    function testRedeemtETH() public {
        address user = vm.addr(1);
        vm.label(user, "user");
        uint256 tethAmt = 1000e18;
        deal(tETH, user, tethAmt);
        vm.startPrank(user);
        IERC20(tETH).approve(address(router), tethAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(terminalAdapter),
            tokenIn: tETH,
            tokenOut: weEth,
            swapData: abi.encode(
                ERC4626VaultAdapterV2.Action.Redeem, tETHRedeemVault, tethAmt, tethAmt * 8 / 10, bytes32(0)
            ) // inAmount, minReceiveAmount
        });
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: tethAmt, useBalanceOnchain: false});

        uint256 susdeBefore = IERC20(susde).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 susdeAfter = IERC20(susde).balanceOf(user);
        console.log("susde out", susdeAfter - susdeBefore);
    }

    function testDepositTETH() public {
        address user = vm.addr(1);
        vm.label(user, "user");
        uint256 ethAmt = 620322893826950;
        deal(weth, user, ethAmt);
        vm.startPrank(user);
        IERC20(weth).approve(address(router), ethAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(terminalAdapter),
            tokenIn: weth,
            tokenOut: tETH,
            swapData: abi.encode(
                ERC4626VaultAdapterV2.Action.Deposit, tETHDepositVault, ethAmt, ethAmt * 8 / 10, bytes32(0)
            ) // inAmount, minReceiveAmount, referrerId
        });
        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: ethAmt, useBalanceOnchain: false});

        uint256 tETHBefore = IERC20(tETH).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 tETHAfter = IERC20(tETH).balanceOf(user);
        console.log("tETH out", tETHAfter - tETHBefore);
    }
}
