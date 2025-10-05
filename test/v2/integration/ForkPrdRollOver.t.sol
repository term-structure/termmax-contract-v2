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
import {
    ForkBaseTestV2,
    TermMaxFactoryV2,
    MarketConfig,
    IERC20,
    MarketInitialParams,
    IERC20Metadata
} from "test/v2/mainnet-fork/ForkBaseTestV2.sol";
import {TermMaxSwapData, TermMaxSwapAdapter} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
import {IWhitelistManager} from "contracts/v2/access/IWhitelistManager.sol";
import {console} from "forge-std/console.sol";
import {RouterErrorsV2} from "contracts/v2/errors/RouterErrorsV2.sol";

interface TestOracle is IOracle {
    function acceptPendingOracle(address asset) external;
    function oracles(address asset) external returns (address aggregator, address backupAggregator, uint32 heartbeat);
}

contract ForkPrdRollover is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    uint64 may_30 = 1748534400; // 2025-05-30 00:00:00
    uint64 aug_1 = 1753977600; // 2025-08-01 00:00:00
    address pt_susde_may_29 = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
    address pt_susde_jun_31 = 0x3b3fB9C57858EF816833dC91565EFcd85D96f634;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address susde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    TestOracle oracle = TestOracle(0xE3a31690392E8E18DC3d862651C079339E2c1ADE);

    ITermMaxMarket mmay_30 = ITermMaxMarket(0xe867255dC0c3a27c90f756ECC566a5292ce19492);
    ITermMaxMarket maug_1 = ITermMaxMarket(0xdBB2D44c238c459cCB820De886ABF721EF6E6941);
    ITermMaxOrder o_may_30 = ITermMaxOrder(0xe99ee5b18cB57276EbEADf0E773E4f8Ab49Db9B7);
    ITermMaxOrder o_aug_1 = ITermMaxOrder(0x71Df74d65c3895C8FA5a1c8E8d93A7eE30A1aFc7);
    address pendleAdapter;
    address odosAdapter;
    address tmxAdapter;
    TermMaxRouterV2 router;

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        vm.rollFork(22486319); // 2025-05-15
        // vm.warp(1747256663);

        address accessManager = Ownable(address(oracle)).owner();
        vm.startPrank(accessManager);
        address[] memory tokens = new address[](4);
        tokens[0] = usdc;
        tokens[1] = susde;
        tokens[2] = pt_susde_may_29;
        tokens[3] = pt_susde_jun_31;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            (address aggregator, address backupAggregator,) = oracle.oracles(token);
            IOracle.Oracle memory oracleData = IOracle.Oracle({
                aggregator: AggregatorV3Interface(aggregator),
                backupAggregator: AggregatorV3Interface(backupAggregator),
                heartbeat: 365 days
            });
            oracle.submitPendingOracle(token, oracleData);
        }
        vm.warp(block.timestamp + 1 days);
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            oracle.acceptPendingOracle(token);
        }

        vm.stopPrank();

        PendleSwapV3AdapterV2 adapter = new PendleSwapV3AdapterV2(0x888888888889758F76e7103c6CbF23ABbF58F946);
        pendleAdapter = address(adapter);

        OdosV2AdapterV2 od = new OdosV2AdapterV2(0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559);
        odosAdapter = address(od);

        vm.label(pt_susde_may_29, "pt_susde_may_29");
        vm.label(pt_susde_jun_31, "pt_susde_jun_31");
        vm.label(susde, "susde");
        vm.label(address(oracle), "oracle");
        vm.label(address(mmay_30), "mmay_30");
        vm.label(address(maug_1), "maug_1");
        vm.label(address(o_may_30), "o_may_30");
        vm.label(address(o_aug_1), "o_aug_1");
        vm.label(address(pendleAdapter), "pendleAdapter");

        address admin = vm.randomAddress();

        vm.startPrank(admin);
        IWhitelistManager whitelistManager;
        (router, whitelistManager) = deployRouter(admin);
        router.setWhitelistManager(address(whitelistManager));

        TermMaxSwapAdapter tmx = new TermMaxSwapAdapter(address(whitelistManager));
        tmxAdapter = address(tmx);
        vm.label(tmxAdapter, "TermMaxAdapter");

        address[] memory adapters = new address[](3);
        adapters[0] = pendleAdapter;
        adapters[1] = odosAdapter;
        adapters[2] = tmxAdapter;
        whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);

        address[] memory callbacks = new address[](2);
        callbacks[0] = address(ITermMaxOrder(o_may_30).orderConfig().swapTrigger);
        callbacks[1] = address(ITermMaxOrder(o_aug_1).orderConfig().swapTrigger);
        whitelistManager.batchSetWhitelist(callbacks, IWhitelistManager.ContractModule.ORDER_CALLBACK, true);
        vm.stopPrank();
    }

    function testRolloverPt() public {
        uint128 debt;
        uint256 collateralAmount;
        // deal(pt_susde_may_29, borrower, collateralAmount);
        uint256 gt1 = 5;
        address borrower;
        {
            (,, IGearingToken gt,,) = mmay_30.tokens();
            (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(gt1);
            borrower = owner;
            debt = debtAmt;
            collateralAmount = abi.decode(collateralData, (uint256));
            console.log("collateralAmount:", collateralAmount);
            console.log("debt:", debt);
        }
        vm.startPrank(borrower);
        vm.warp(may_30 - 0.5 days);
        // roll gt
        {
            address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
            address pm2 = 0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac;

            SwapUnit[] memory swapUnits = new SwapUnit[](2);
            swapUnits[0] = SwapUnit({
                adapter: pendleAdapter,
                tokenIn: pt_susde_may_29,
                tokenOut: susde,
                swapData: abi.encode(pm1, collateralAmount, 0)
            });
            swapUnits[1] = SwapUnit({
                adapter: pendleAdapter,
                tokenIn: susde,
                tokenOut: pt_susde_jun_31,
                swapData: abi.encode(pm2, 1e18, 0)
            });

            SwapPath memory collateralPath = SwapPath({
                units: swapUnits,
                recipient: address(router),
                inputAmount: collateralAmount,
                useBalanceOnchain: false
            });

            uint256 additionalAssets = debt / 10;

            address[] memory orders = new address[](1);
            orders[0] = address(o_aug_1);
            uint128[] memory amounts = new uint128[](1);
            amounts[0] = debt - uint128(additionalAssets);
            (IERC20 ft,, IGearingToken gt, address collateral,) = mmay_30.tokens();

            deal(usdc, borrower, additionalAssets);
            IERC20(usdc).approve(address(router), additionalAssets);
            gt.approve(address(router), gt1);

            (IERC20 ft_aug_1,,,,) = maug_1.tokens();
            TermMaxSwapData memory swapData = TermMaxSwapData({
                swapExactTokenForToken: false,
                scalingFactor: 0,
                orders: orders,
                tradingAmts: amounts,
                netTokenAmt: debt,
                deadline: aug_1
            });
            SwapUnit[] memory swapUnits2 = new SwapUnit[](1);
            swapUnits2[0] = SwapUnit({
                adapter: address(tmxAdapter),
                tokenIn: address(ft_aug_1),
                tokenOut: address(usdc),
                swapData: abi.encode(swapData)
            });
            // swap ft to usdc, the inputAmount is the ft amount you want to issue
            SwapPath memory debtPaths =
                SwapPath({units: swapUnits2, recipient: address(router), inputAmount: debt, useBalanceOnchain: true});

            uint128 maxLtv = 0.9e8;
            bytes memory rolloverData =
                abi.encode(FlashRepayOptions.ROLLOVER, abi.encode(borrower, maug_1, maxLtv, collateralPath, debtPaths));
            uint256 additionalAmt = additionalAssets;
            IERC20 additionalAsset = IERC20(usdc);
            uint256 gtId2 = router.rolloverGt(gt, gt1, additionalAsset, additionalAmt, rolloverData);
            console.log("new gtId:", gtId2);
        }

        vm.stopPrank();
    }

    function testRolloverPtWithCollateral() public {
        uint128 debt;
        uint256 collateralAmount;
        // deal(pt_susde_may_29, borrower, collateralAmount);
        uint256 gt1 = 5;
        address borrower;
        {
            (,, IGearingToken gt,,) = mmay_30.tokens();
            (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(gt1);
            borrower = owner;
            debt = debtAmt;
            collateralAmount = abi.decode(collateralData, (uint256));
            console.log("collateralAmount:", collateralAmount);
            console.log("debt:", debt);
        }
        vm.startPrank(borrower);
        vm.warp(may_30 - 0.5 days);
        // roll gt
        {
            address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
            address pm2 = 0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac;

            SwapUnit[] memory swapUnits = new SwapUnit[](2);
            swapUnits[0] = SwapUnit({
                adapter: pendleAdapter,
                tokenIn: pt_susde_may_29,
                tokenOut: susde,
                swapData: abi.encode(pm1, collateralAmount, 0)
            });
            swapUnits[1] = SwapUnit({
                adapter: pendleAdapter,
                tokenIn: susde,
                tokenOut: pt_susde_jun_31,
                swapData: abi.encode(pm2, 1e18, 0)
            });

            uint256 additionalCollateral = 0.2 ether;

            SwapPath memory collateralPath = SwapPath({
                units: swapUnits,
                recipient: address(router),
                inputAmount: collateralAmount,
                useBalanceOnchain: false
            });

            address[] memory orders = new address[](1);
            orders[0] = address(o_aug_1);
            uint128[] memory amounts = new uint128[](1);
            amounts[0] = debt;
            (IERC20 ft,, IGearingToken gt, address collateral,) = mmay_30.tokens();

            deal(pt_susde_jun_31, borrower, additionalCollateral);
            IERC20(pt_susde_jun_31).approve(address(router), additionalCollateral);
            gt.approve(address(router), gt1);

            (IERC20 ft_aug_1,,,,) = maug_1.tokens();

            TermMaxSwapData memory swapData = TermMaxSwapData({
                swapExactTokenForToken: false,
                scalingFactor: 0,
                orders: orders,
                tradingAmts: amounts,
                netTokenAmt: debt + debt / 15,
                deadline: aug_1
            });
            SwapUnit[] memory swapUnits2 = new SwapUnit[](1);
            swapUnits2[0] = SwapUnit({
                adapter: address(tmxAdapter),
                tokenIn: address(ft_aug_1),
                tokenOut: address(usdc),
                swapData: abi.encode(swapData)
            });
            // swap ft to usdc, the inputAmount is the ft amount you want to issue
            SwapPath memory debtPaths = SwapPath({
                units: swapUnits2,
                recipient: address(router),
                inputAmount: debt + debt / 15,
                useBalanceOnchain: true
            });

            uint128 maxLtv = 0.9e8;
            bytes memory rolloverData =
                abi.encode(FlashRepayOptions.ROLLOVER, abi.encode(borrower, maug_1, maxLtv, collateralPath, debtPaths));

            uint256 additionalAmt = additionalCollateral;
            IERC20 additionalAsset = IERC20(pt_susde_jun_31);
            uint256 gtId2 = router.rolloverGt(gt, gt1, additionalAsset, additionalAmt, rolloverData);
            console.log("new gtId:", gtId2);
        }

        vm.stopPrank();
    }

    function testRolloverPtWithOldCollateral() public {
        uint128 debt;
        uint256 collateralAmount;
        // deal(pt_susde_may_29, borrower, collateralAmount);
        uint256 gt1 = 5;
        address borrower;
        {
            (,, IGearingToken gt,,) = mmay_30.tokens();
            (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(gt1);
            borrower = owner;
            debt = debtAmt;
            collateralAmount = abi.decode(collateralData, (uint256));
            console.log("collateralAmount:", collateralAmount);
            console.log("debt:", debt);
        }
        vm.startPrank(borrower);
        vm.warp(may_30 - 0.5 days);
        // roll gt
        {
            address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
            address pm2 = 0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac;

            uint256 additionalCollateral = 0.2 ether;

            SwapUnit[] memory swapUnits = new SwapUnit[](2);
            swapUnits[0] = SwapUnit({
                adapter: pendleAdapter,
                tokenIn: pt_susde_may_29,
                tokenOut: susde,
                swapData: abi.encode(pm1, collateralAmount, 0)
            });
            swapUnits[1] = SwapUnit({
                adapter: pendleAdapter,
                tokenIn: susde,
                tokenOut: pt_susde_jun_31,
                swapData: abi.encode(pm2, 1e18, 0)
            });

            SwapPath memory collateralPath = SwapPath({
                units: swapUnits,
                recipient: address(router),
                inputAmount: collateralAmount + additionalCollateral,
                useBalanceOnchain: false
            });

            address[] memory orders = new address[](1);
            orders[0] = address(o_aug_1);
            uint128[] memory amounts = new uint128[](1);
            amounts[0] = debt;
            (IERC20 ft,, IGearingToken gt, address collateral,) = mmay_30.tokens();
            IERC20 additionalAsset = IERC20(pt_susde_may_29);
            deal(address(additionalAsset), borrower, additionalCollateral);
            additionalAsset.approve(address(router), additionalCollateral);
            gt.approve(address(router), gt1);

            (IERC20 ft_aug_1,,,,) = maug_1.tokens();

            TermMaxSwapData memory swapData = TermMaxSwapData({
                swapExactTokenForToken: false,
                scalingFactor: 0,
                orders: orders,
                tradingAmts: amounts,
                netTokenAmt: debt + debt / 15,
                deadline: aug_1
            });
            SwapUnit[] memory swapUnits2 = new SwapUnit[](1);
            swapUnits2[0] = SwapUnit({
                adapter: address(tmxAdapter),
                tokenIn: address(ft_aug_1),
                tokenOut: address(usdc),
                swapData: abi.encode(swapData)
            });
            // swap ft to usdc, the inputAmount is the ft amount you want to issue
            SwapPath memory debtPaths = SwapPath({
                units: swapUnits2,
                recipient: address(router),
                inputAmount: debt + debt / 15,
                useBalanceOnchain: true
            });

            uint128 maxLtv = 0.9e8;
            bytes memory rolloverData =
                abi.encode(FlashRepayOptions.ROLLOVER, abi.encode(borrower, maug_1, maxLtv, collateralPath, debtPaths));

            uint256 gtId2 = router.rolloverGt(gt, gt1, additionalAsset, additionalCollateral, rolloverData);
            console.log("new gtId:", gtId2);
        }

        vm.stopPrank();
    }

    // function testRolloverPtV2() public {
    //     address borrower = vm.randomAddress();
    //     vm.label(borrower, "borrower");
    //     address admin = vm.randomAddress();
    //     vm.label(admin, "admin");

    //     vm.startPrank(admin);
    //     ITermMaxMarket market;
    //     uint256 gtId1;
    //     uint128 oldDebt = 100e6;
    //     uint256 oldCollateral = 1000e18;

    //     deal(pt_susde_may_29, admin, oldCollateral);

    //     // create new market support v2 flash repay
    //     {
    //         TermMaxFactoryV2 f2 = deployFactory(admin);
    //         MarketConfig memory marketConfig = mmay_30.config();
    //         (,, IGearingToken gt, address collateral, IERC20 debtToken) = mmay_30.tokens();
    //         GtConfig memory gtConfig = gt.getGtConfig();
    //         MarketInitialParams memory params = MarketInitialParams({
    //             collateral: collateral,
    //             debtToken: IERC20Metadata(address(debtToken)),
    //             admin: admin,
    //             gtImplementation: address(0),
    //             marketConfig: marketConfig,
    //             loanConfig: gtConfig.loanConfig,
    //             gtInitalParams: abi.encode(type(uint128).max),
    //             tokenName: "Test",
    //             tokenSymbol: "TEST"
    //         });
    //         market = ITermMaxMarket(f2.createMarket(keccak256("GearingTokenWithERC20"), params, 1));
    //         vm.label(address(market), "newMarket");

    //         (,, IGearingToken gt2,,) = market.tokens();

    //         IERC20(pt_susde_may_29).approve(address(gt2), oldCollateral);
    //         (gtId1,) = market.issueFt(borrower, 100e6, abi.encode(oldCollateral));

    //         vm.label(address(market), "market_may_30");
    //         vm.label(address(gt2), "gt_may_30");
    //     }

    //     vm.stopPrank();

    //     uint128 debt = 20e6;
    //     uint256 collateralAmount = 500e18;

    //     vm.startPrank(borrower);
    //     vm.warp(may_30 - 0.5 days);
    //     // roll gt
    //     {
    //         address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
    //         address pm2 = 0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac;

    //         SwapUnit[] memory swapUnits = new SwapUnit[](2);
    //         swapUnits[0] = SwapUnit({
    //             adapter: pendleAdapter,
    //             tokenIn: pt_susde_may_29,
    //             tokenOut: susde,
    //             swapData: abi.encode(pm1, collateralAmount, 0)
    //         });
    //         swapUnits[1] = SwapUnit({
    //             adapter: pendleAdapter,
    //             tokenIn: susde,
    //             tokenOut: pt_susde_jun_31,
    //             swapData: abi.encode(pm2, 1e18, 0)
    //         });
    //         SwapPath memory collateralPath = SwapPath({
    //             units: swapUnits,
    //             recipient: address(router),
    //             inputAmount: collateralAmount,
    //             useBalanceOnchain: false
    //         });

    //         uint128 additionalAssets = debt / 10;

    //         address[] memory orders = new address[](1);
    //         orders[0] = address(o_aug_1);
    //         uint128[] memory amounts = new uint128[](1);
    //         amounts[0] = debt - additionalAssets;
    //         (IERC20 ft,, IGearingToken gt, address collateral,) = market.tokens();

    //         deal(usdc, borrower, additionalAssets);
    //         IERC20(usdc).approve(address(router), additionalAssets);
    //         gt.approve(address(router), gtId1);

    //         (IERC20 ft_aug_1,,,,) = maug_1.tokens();

    //         TermMaxSwapData memory swapData = TermMaxSwapData({
    //             swapExactTokenForToken: false,
    //             scalingFactor: 0,
    //             orders: orders,
    //             tradingAmts: amounts,
    //             netTokenAmt: debt,
    //             deadline: aug_1
    //         });
    //         SwapUnit[] memory swapUnits2 = new SwapUnit[](1);
    //         swapUnits2[0] = SwapUnit({
    //             adapter: address(tmxAdapter),
    //             tokenIn: address(ft_aug_1),
    //             tokenOut: address(usdc),
    //             swapData: abi.encode(swapData)
    //         });
    //         // swap ft to usdc, the inputAmount is the ft amount you want to issue
    //         SwapPath memory debtPaths =
    //             SwapPath({units: swapUnits2, recipient: address(router), inputAmount: debt, useBalanceOnchain: false});

    //         uint128 maxLtv = 0.9e8;
    //         bytes memory rolloverData =
    //             abi.encode(FlashRepayOptions.ROLLOVER, abi.encode(borrower, maug_1, maxLtv, collateralPath, debtPaths));
    //         uint256 additionalAmt = additionalAssets;
    //         IERC20 additionalAsset = IERC20(usdc);
    //         uint256 gtId2 =
    //             router.rolloverGtForV2(gt, gtId1, debt, collateralAmount, additionalAsset, additionalAmt, rolloverData);

    //         (address owner, uint128 currentDebt, bytes memory currentCollateral) = gt.loanInfo(gtId1);
    //         assertEq(owner, borrower, "borrower should be the same");
    //         assertEq(currentDebt + debt, oldDebt, "debt should be the same");
    //         assertEq(
    //             abi.decode(currentCollateral, (uint256)),
    //             oldCollateral - collateralAmount,
    //             "collateral should be the same"
    //         );

    //         (,, IGearingToken gt2,,) = maug_1.tokens();
    //         console.log("new gtId:", gtId2);
    //         (address owner2, uint128 currentDebt2, bytes memory currentCollateral2) = gt2.loanInfo(gtId2);
    //         assertEq(owner2, borrower, "borrower should be the same");
    //         console.log("new gt debt:", currentDebt2 / 1e6);
    //         console.log("new gt collateral:", abi.decode(currentCollateral2, (uint256)) / 1e18);
    //     }

    //     vm.stopPrank();
    // }

    // function testFrontRunRolloverPtV2() public {
    //     address borrower = vm.randomAddress();
    //     vm.label(borrower, "borrower");
    //     address admin = vm.randomAddress();
    //     vm.label(admin, "admin");

    //     vm.startPrank(admin);
    //     ITermMaxMarket market;
    //     uint256 gtId1;
    //     uint128 oldDebt = 100e6;
    //     uint256 oldCollateral = 1000e18;

    //     deal(pt_susde_may_29, admin, oldCollateral);

    //     // create new market support v2 flash repay
    //     {
    //         TermMaxFactoryV2 f2 = deployFactory(admin);
    //         MarketConfig memory marketConfig = mmay_30.config();
    //         (,, IGearingToken gt, address collateral, IERC20 debtToken) = mmay_30.tokens();
    //         GtConfig memory gtConfig = gt.getGtConfig();
    //         MarketInitialParams memory params = MarketInitialParams({
    //             collateral: collateral,
    //             debtToken: IERC20Metadata(address(debtToken)),
    //             admin: admin,
    //             gtImplementation: address(0),
    //             marketConfig: marketConfig,
    //             loanConfig: gtConfig.loanConfig,
    //             gtInitalParams: abi.encode(type(uint128).max),
    //             tokenName: "Test",
    //             tokenSymbol: "TEST"
    //         });
    //         market = ITermMaxMarket(f2.createMarket(keccak256("GearingTokenWithERC20"), params, 1));
    //         vm.label(address(market), "newMarket");

    //         (,, IGearingToken gt2,,) = market.tokens();

    //         IERC20(pt_susde_may_29).approve(address(gt2), oldCollateral);
    //         (gtId1,) = market.issueFt(borrower, oldDebt, abi.encode(oldCollateral));

    //         vm.label(address(market), "market_may_30");
    //         vm.label(address(gt2), "gt_may_30");
    //     }

    //     vm.stopPrank();

    //     uint128 debt = 20e6;
    //     uint256 collateralAmount = 500e18;

    //     vm.startPrank(borrower);
    //     vm.warp(may_30 - 0.5 days);
    //     // roll gt
    //     {
    //         address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
    //         address pm2 = 0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac;

    //         SwapUnit[] memory swapUnits = new SwapUnit[](2);
    //         swapUnits[0] = SwapUnit({
    //             adapter: pendleAdapter,
    //             tokenIn: pt_susde_may_29,
    //             tokenOut: susde,
    //             swapData: abi.encode(pm1, collateralAmount, 0)
    //         });
    //         swapUnits[1] = SwapUnit({
    //             adapter: pendleAdapter,
    //             tokenIn: susde,
    //             tokenOut: pt_susde_jun_31,
    //             swapData: abi.encode(pm2, 1e18, 0)
    //         });
    //         SwapPath memory collateralPath = SwapPath({
    //             units: swapUnits,
    //             recipient: address(router),
    //             inputAmount: collateralAmount,
    //             useBalanceOnchain: false
    //         });

    //         uint128 additionalAssets = debt / 10;

    //         address[] memory orders = new address[](1);
    //         orders[0] = address(o_aug_1);
    //         uint128[] memory amounts = new uint128[](1);
    //         amounts[0] = debt - additionalAssets;
    //         (IERC20 ft,, IGearingToken gt, address collateral,) = market.tokens();

    //         deal(usdc, borrower, additionalAssets);
    //         IERC20(usdc).approve(address(router), additionalAssets);
    //         gt.approve(address(router), gtId1);

    //         (IERC20 ft_aug_1,,,,) = maug_1.tokens();

    //         TermMaxSwapData memory swapData = TermMaxSwapData({
    //             swapExactTokenForToken: false,
    //             scalingFactor: 0,
    //             orders: orders,
    //             tradingAmts: amounts,
    //             netTokenAmt: debt,
    //             deadline: aug_1
    //         });
    //         SwapUnit[] memory swapUnits2 = new SwapUnit[](1);
    //         swapUnits2[0] = SwapUnit({
    //             adapter: address(tmxAdapter),
    //             tokenIn: address(ft_aug_1),
    //             tokenOut: address(usdc),
    //             swapData: abi.encode(swapData)
    //         });
    //         // swap ft to usdc, the inputAmount is the ft amount you want to issue
    //         SwapPath memory debtPaths =
    //             SwapPath({units: swapUnits2, recipient: address(router), inputAmount: debt, useBalanceOnchain: false});

    //         uint128 maxLtv = 0.9e8;
    //         bytes memory rolloverData =
    //             abi.encode(FlashRepayOptions.ROLLOVER, abi.encode(borrower, maug_1, maxLtv, collateralPath, debtPaths));
    //         uint256 additionalAmt = additionalAssets;
    //         IERC20 additionalAsset = IERC20(usdc);
    //         uint128 repayAmt = oldDebt - debt;
    //         deal(usdc, borrower, repayAmt + additionalAmt);
    //         IERC20(usdc).approve(address(gt), repayAmt + additionalAmt);
    //         gt.repay(gtId1, repayAmt, true);

    //         vm.expectRevert(abi.encodeWithSelector(RouterErrorsV2.RemovedCollateralNotMatch.selector));
    //         router.rolloverGtForV2(gt, gtId1, debt, collateralAmount, additionalAsset, additionalAmt, rolloverData);
    //     }

    //     vm.stopPrank();
    // }
}
