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
import {PendleSyAdapter, IStandardizedYield} from "contracts/v2/router/swapAdapters/PendleSyAdapter.sol";
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {console} from "forge-std/console.sol";

contract ForkPendleSyAdapter is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    // Tokens
    address susde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address sy_susde = 0x50CBf8837791aB3D8dcfB3cE3d1B0d128e1105d4; // standardized yield token for sUSDE
    address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    TermMaxRouterV2 router;
    PendleSyAdapter pendleSyAdapter;

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        pendleSyAdapter = new PendleSyAdapter();

        vm.label(susde, "sUSDE");
        vm.label(sy_susde, "SY-sUSDE");
        vm.label(usde, "USDe");
        vm.label(address(pendleSyAdapter), "PendleSyAdapter");

        address admin = vm.randomAddress();

        vm.startPrank(admin);
        IWhitelistManager whitelistManager;
        (router, whitelistManager) = deployRouter(admin);
        router.setWhitelistManager(address(whitelistManager));

        address[] memory adapters = new address[](1);
        adapters[0] = address(pendleSyAdapter);
        whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);
        vm.stopPrank();
    }

    // ============ Deposit Tests (Underlying -> SY Token) ============

    /**
     * @notice Test depositing sUSDE to get SY-sUSDE
     * @dev Tests the Deposit action of PendleSyAdapter
     */
    function testDepositSUSDEToSY() public {
        address user = vm.addr(1);
        vm.label(user, "user");

        uint256 susdeAmount = 100_000e18;
        deal(susde, user, susdeAmount);

        vm.startPrank(user);
        IERC20(susde).approve(address(router), susdeAmount);

        uint256 minSyOut = IStandardizedYield(sy_susde).previewDeposit(susde, susdeAmount);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(pendleSyAdapter),
            tokenIn: susde,
            tokenOut: sy_susde,
            swapData: abi.encode(
                ERC4626VaultAdapterV2.Action.Deposit,
                susdeAmount, // inAmount
                minSyOut // minTokenOut
            )
        });

        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: susdeAmount, useBalanceOnchain: false});

        uint256 syBefore = IERC20(sy_susde).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 syAfter = IERC20(sy_susde).balanceOf(user);
        uint256 syReceived = syAfter - syBefore;

        console.log("sUSDE deposited:", susdeAmount);
        console.log("SY-sUSDE received:", syReceived);

        assertGt(syReceived, 0, "Should receive SY tokens");
        assertGe(syReceived, minSyOut, "Should receive at least minimum SY tokens");
        vm.stopPrank();
    }

    /**
     * @notice Test depositing USDe to get SY-sUSDE
     * @dev Tests depositing the base asset (USDe) directly to SY
     */
    function testDepositUSDeToSY() public {
        address user = vm.addr(1);
        vm.label(user, "user");

        uint256 usdeAmount = 100_000e18;
        deal(usde, user, usdeAmount);

        vm.startPrank(user);
        IERC20(usde).approve(address(router), usdeAmount);

        uint256 minSyOut = IStandardizedYield(sy_susde).previewDeposit(usde, usdeAmount);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(pendleSyAdapter),
            tokenIn: usde,
            tokenOut: sy_susde,
            swapData: abi.encode(
                ERC4626VaultAdapterV2.Action.Deposit,
                usdeAmount, // inAmount
                minSyOut // minTokenOut
            )
        });

        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: usdeAmount, useBalanceOnchain: false});

        uint256 syBefore = IERC20(sy_susde).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 syAfter = IERC20(sy_susde).balanceOf(user);
        uint256 syReceived = syAfter - syBefore;

        console.log("USDe deposited:", usdeAmount);
        console.log("SY-sUSDE received:", syReceived);

        assertGt(syReceived, 0, "Should receive SY tokens");
        assertGe(syReceived, minSyOut, "Should receive at least minimum SY tokens");
        vm.stopPrank();
    }

    // ============ Redeem Tests (SY Token -> Underlying) ============

    /**
     * @notice Test redeeming SY-sUSDE to get sUSDE back
     * @dev Tests the Redeem action of PendleSyAdapter
     */
    function testRedeemSYToSUSDe() public {
        address user = vm.addr(1);
        vm.label(user, "user");

        uint256 syAmount = 50_000e18;
        deal(sy_susde, user, syAmount);

        vm.startPrank(user);
        IERC20(sy_susde).approve(address(router), syAmount);

        // Calculate minimum output (with 2% slippage tolerance)
        uint256 minSusdeOut = IStandardizedYield(sy_susde).previewRedeem(susde, syAmount);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(pendleSyAdapter),
            tokenIn: sy_susde,
            tokenOut: susde,
            swapData: abi.encode(
                ERC4626VaultAdapterV2.Action.Redeem,
                syAmount, // inAmount
                minSusdeOut // minTokenOut
            )
        });

        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: user, inputAmount: syAmount, useBalanceOnchain: false});

        uint256 susdeBefore = IERC20(susde).balanceOf(user);
        router.swapTokens(swapPaths);
        uint256 susdeAfter = IERC20(susde).balanceOf(user);
        uint256 susdeReceived = susdeAfter - susdeBefore;

        console.log("SY-sUSDE redeemed:", syAmount);
        console.log("sUSDE received:", susdeReceived);

        assertGt(susdeReceived, 0, "Should receive sUSDE");
        assertGe(susdeReceived, minSusdeOut, "Should receive at least minimum sUSDE");
        vm.stopPrank();
    }
}
