// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {
    SwapPath,
    SwapUnit,
    ITermMaxRouterV2,
    TermMaxRouterV2,
    FlashRepayOptions
} from "contracts/v2/router/TermMaxRouterV2.sol";
import {
    IGearingToken,
    GearingTokenEvents,
    AbstractGearingToken,
    GtConfig
} from "contracts/v1/tokens/AbstractGearingToken.sol";
import {PendleSwapV3AdapterV2} from "contracts/v2/router/swapAdapters/PendleSwapV3AdapterV2.sol";
import {OdosV2AdapterV2} from "contracts/v2/router/swapAdapters/OdosV2AdapterV2.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {
    ForkBaseTestV2,
    TermMaxFactoryV2,
    MarketConfig,
    IERC20,
    MarketInitialParams,
    IERC20Metadata
} from "test/v2/mainnet-fork/ForkBaseTestV2.sol";
import {TermMaxSwapData, TermMaxSwapAdapter} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
import {console} from "forge-std/console.sol";
import {IAaveV3PoolMinimal} from "contracts/v2/extensions/aave/IAaveV3PoolMinimal.sol";
import {IAaveV3Minimal} from "contracts/v2/extensions/aave/IAaveV3Minimal.sol";
import {ICreditDelegationToken} from "contracts/v2/extensions/aave/ICreditDelegationToken.sol";
import {IMorpho, Id, MarketParams, Authorization, Signature} from "contracts/v2/extensions/morpho/IMorpho.sol";

interface TestOracle is IOracle {
    function acceptPendingOracle(address asset) external;
    function oracles(address asset) external returns (address aggregator, address backupAggregator, uint32 heartbeat);
}

contract ForkPrdRollOverToThird is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    uint64 may_30 = 1748534400; // 2025-05-30 00:00:00
    address pt_susde_may_29 = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
    address pt_susde_jul_31 = 0x3b3fB9C57858EF816833dC91565EFcd85D96f634;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address susde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    TestOracle oracle = TestOracle(0xE3a31690392E8E18DC3d862651C079339E2c1ADE);

    ITermMaxMarket mmay_30 = ITermMaxMarket(0xe867255dC0c3a27c90f756ECC566a5292ce19492);

    ITermMaxMarket mjul_31 = ITermMaxMarket(0xdBB2D44c238c459cCB820De886ABF721EF6E6941);

    address pendleAdapter;
    address odosAdapter;
    address tmxAdapter;
    address vaultAdapter;
    TermMaxRouterV2 router;
    IAaveV3PoolMinimal aave = IAaveV3PoolMinimal(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    ICreditDelegationToken aaveDebtToken;

    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    Id morpho_market_id = Id.wrap(0xbc552f0b14dd6f8e60b760a534ac1d8613d3539153b4d9675d697e048f2edc7e);

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function _initResourcesWithBlockNumber(uint256 blockNumber) internal {
        vm.rollFork(blockNumber);
        PendleSwapV3AdapterV2 adapter = new PendleSwapV3AdapterV2(0x888888888889758F76e7103c6CbF23ABbF58F946);
        pendleAdapter = address(adapter);

        OdosV2AdapterV2 od = new OdosV2AdapterV2(0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559);
        odosAdapter = address(od);

        TermMaxSwapAdapter tmx = new TermMaxSwapAdapter();
        tmxAdapter = address(tmx);
        vm.label(tmxAdapter, "TermMaxAdapter");

        vaultAdapter = address(new ERC4626VaultAdapterV2());
        vm.label(vaultAdapter, "ERC4626VaultAdapterV2");

        vm.label(pt_susde_may_29, "pt_susde_may_29");
        vm.label(susde, "susde");
        vm.label(address(oracle), "oracle");
        vm.label(address(mmay_30), "mmay_30");
        vm.label(address(pendleAdapter), "pendleAdapter");

        address admin = vm.randomAddress();

        vm.startPrank(admin);
        router = deployRouter(admin);
        router.setAdapterWhitelist(pendleAdapter, true);
        router.setAdapterWhitelist(odosAdapter, true);
        router.setAdapterWhitelist(tmxAdapter, true);
        router.setAdapterWhitelist(vaultAdapter, true);
        vm.stopPrank();

        IAaveV3Minimal.ReserveData memory rd = IAaveV3Minimal(address(aave)).getReserveData(usdc);
        aaveDebtToken = ICreditDelegationToken(rd.variableDebtTokenAddress);
    }

    function testRolloverPtToAave() public {
        _initResourcesWithBlockNumber(22486319); // 2025-05-15
        uint128 debt;
        uint256 collateralAmount;
        uint256 gt1;
        address borrower = vm.randomAddress();
        vm.startPrank(borrower);
        {
            (,, IGearingToken gt,,) = mmay_30.tokens();
            // create a new debt position
            debt = 2012814397;
            collateralAmount = 2501271245527830095803;
            deal(pt_susde_may_29, borrower, collateralAmount);
            IERC20(pt_susde_may_29).approve(address(gt), collateralAmount);
            (gt1,) = mmay_30.issueFt(borrower, debt, abi.encode(collateralAmount));
            console.log("collateralAmount:", collateralAmount);
            console.log("debt:", debt);
        }

        vm.warp(may_30 - 0.5 days);
        // roll gt
        {
            address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;

            SwapUnit[] memory swapUnits = new SwapUnit[](1);
            swapUnits[0] = SwapUnit({
                adapter: pendleAdapter,
                tokenIn: pt_susde_may_29,
                tokenOut: susde,
                swapData: abi.encode(pm1, collateralAmount, 0)
            });
            SwapPath memory collateralPath =
                SwapPath({units: swapUnits, recipient: address(router), inputAmount: 0, useBalanceOnchain: true});

            uint256 additionalAmt = debt / 3;
            IERC20 additionalAsset = IERC20(usdc);
            (IERC20 ft,, IGearingToken gt, address collateral,) = mmay_30.tokens();

            deal(address(additionalAsset), borrower, additionalAmt);
            additionalAsset.approve(address(router), additionalAmt);
            aaveDebtToken.approveDelegation(address(router), debt - additionalAmt);
            gt.approve(address(router), gt1);
            // 1-stable 2-variable
            uint256 interestRateMode = 2;
            uint16 referralCode = 0;
            bytes memory rolloverData = abi.encode(
                FlashRepayOptions.ROLLOVER_AAVE,
                abi.encode(borrower, collateral, aave, interestRateMode, referralCode, collateralPath)
            );

            router.rolloverGtForV1(gt, gt1, additionalAsset, additionalAmt, rolloverData);
        }

        vm.stopPrank();
    }

    function testRolloverPtToMorphoForV1() public {
        _initResourcesWithBlockNumber(22985670); // 2025-07-24
        uint128 debt;
        uint256 collateralAmount;
        uint256 gt1;
        address borrower = vm.randomAddress();
        vm.startPrank(borrower);
        {
            (,, IGearingToken gt,,) = mjul_31.tokens();
            // create a new debt position
            debt = 2448639688;
            collateralAmount = 2869261070978839154575;
            deal(pt_susde_jul_31, borrower, collateralAmount);
            IERC20(pt_susde_jul_31).approve(address(gt), collateralAmount);
            (gt1,) = mjul_31.issueFt(borrower, debt, abi.encode(collateralAmount));
            console.log("collateralAmount:", collateralAmount);
            console.log("debt:", debt);
        }
        // roll gt
        {
            Id marketId = morpho_market_id;

            SwapPath memory collateralPath;

            uint256 additionalAmt = debt / 3;
            IERC20 additionalAsset = IERC20(usdc);

            (IERC20 ft,, IGearingToken gt, address collateral,) = mjul_31.tokens();

            deal(usdc, borrower, additionalAmt);
            IERC20(usdc).approve(address(router), additionalAmt);
            // Approve delegation for Morphos
            morpho.setAuthorization(address(router), true);

            gt.approve(address(router), gt1);

            bytes memory rolloverData = abi.encode(
                FlashRepayOptions.ROLLOVER_MORPHO, abi.encode(borrower, collateral, morpho, marketId, collateralPath)
            );
            router.rolloverGtForV1(gt, gt1, additionalAsset, additionalAmt, rolloverData);
        }

        vm.stopPrank();
    }
}
