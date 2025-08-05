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
import {console} from "forge-std/console.sol";

interface TestOracle is IOracle {
    function acceptPendingOracle(address asset) external;
    function oracles(address asset) external returns (address aggregator, address backupAggregator, uint32 heartbeat);
}

contract ForkPrdFlashRepay is ForkBaseTestV2 {
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
    TermMaxRouterV2 router;

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        vm.rollFork(22486319); // 2025-05-15

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
        router = deployRouter(admin);
        router.setAdapterWhitelist(pendleAdapter, true);
        router.setAdapterWhitelist(odosAdapter, true);
        vm.stopPrank();
    }

    function testFlashRepayPtV2() public {
        address borrower = vm.randomAddress();
        vm.label(borrower, "borrower");
        address admin = vm.randomAddress();
        vm.label(admin, "admin");

        vm.startPrank(admin);
        ITermMaxMarket market;
        uint256 gtId1;
        uint128 oldDebt = 1000e6;
        uint256 oldCollateral = 35012712455278300958037;

        deal(pt_susde_may_29, admin, oldCollateral);

        // create new market support v2 flash repay
        {
            TermMaxFactoryV2 f2 = deployFactory(admin);
            MarketConfig memory marketConfig = mmay_30.config();
            (,, IGearingToken gt, address collateral, IERC20 debtToken) = mmay_30.tokens();
            GtConfig memory gtConfig = gt.getGtConfig();
            MarketInitialParams memory params = MarketInitialParams({
                collateral: collateral,
                debtToken: IERC20Metadata(address(debtToken)),
                admin: admin,
                gtImplementation: address(0),
                marketConfig: marketConfig,
                loanConfig: gtConfig.loanConfig,
                gtInitalParams: abi.encode(type(uint128).max),
                tokenName: "Test",
                tokenSymbol: "TEST"
            });
            market = ITermMaxMarket(f2.createMarket(keccak256("GearingTokenWithERC20"), params, 1));
            vm.label(address(market), "newMarket");

            (,, IGearingToken gt2,,) = market.tokens();

            IERC20(pt_susde_may_29).approve(address(gt2), oldCollateral);
            (gtId1,) = market.issueFt(borrower, oldDebt, abi.encode(oldCollateral));

            vm.label(address(market), "market_may_30");
            vm.label(address(gt2), "gt_may_30");
        }

        vm.stopPrank();
        vm.startPrank(borrower);
        vm.warp(may_30 - 0.5 days);
        uint128 repayAmount = 300e6;
        uint256 removedCollateral = 25012712455278300958037;
        // roll gt
        {
            ITermMaxOrder[] memory orders = new ITermMaxOrder[](0);
            uint128[] memory amounts = new uint128[](0);
            SwapUnit[] memory swapUnits = new SwapUnit[](2);
            address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
            swapUnits[0] = SwapUnit({
                adapter: pendleAdapter,
                tokenIn: pt_susde_may_29,
                tokenOut: susde,
                swapData: abi.encode(pm1, removedCollateral, 0)
            });
            swapUnits[1] = SwapUnit({
                adapter: odosAdapter,
                tokenIn: susde,
                tokenOut: usdc,
                swapData: hex"0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a349700000000000000000000000000000000000000000000048103daed12389fbcc800000000000000000000000076edf8c155a1e0d9b2ad11b04d9671cbc25fee99000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000005d443b21d00000000000000000000000000000000000000000000000000000005b66b4d45000000000000000000000000c47591f5c023e44931c78d5a993834875b79fb11000000000000000000000000000000000000000000000000000000000000014000000000000000000000000076edf8c155a1e0d9b2ad11b04d9671cbc25fee9900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000084010206000d0100010201022700000304000d0101050400ff00000000000000007eb59373d63627be64b42406b108b602174b4ccc9d39a5de30e57443bff2a8307a4256c8797a3497dac17f958d2ee523a2206206994597c13d831ec7c02aaa39b223fe8d0a0e5c4f27ead9083c756cc288e6a0c2ddd26feeb64f039a2c41296fcb3f564000000000000000000000000000000000000000000000000000000000"
            });
            (IERC20 ft,, IGearingToken gt, address collateral,) = market.tokens();
            console.log("usdc balance before:", IERC20(usdc).balanceOf(borrower));
            gt.approve(address(router), gtId1);

            SwapPath[] memory swapPaths = new SwapPath[](1);
            swapPaths[0] =
                SwapPath({units: swapUnits, recipient: address(router), inputAmount: 0, useBalanceOnchain: true});
            bytes memory data = abi.encode(FlashRepayOptions.REPAY, abi.encode(swapPaths));
            router.flashRepayFromCollForV2(borrower, market, gtId1, repayAmount, true, 0, removedCollateral, data);
            console.log("usdc balance after:", IERC20(usdc).balanceOf(borrower));

            (address owner, uint128 currentDebt, bytes memory currentCollateral) = gt.loanInfo(gtId1);
            assertEq(owner, borrower, "borrower should be the same");
            assertEq(currentDebt, oldDebt - repayAmount, "debt should be the same");
            assertEq(
                abi.decode(currentCollateral, (uint256)),
                oldCollateral - removedCollateral,
                "collateral should be the same"
            );
            vm.stopPrank();
        }

        vm.stopPrank();
    }

    function testFlashRepayPt() public {
        address borrower;
        address admin = vm.randomAddress();

        vm.startPrank(admin);
        TermMaxRouterV2 router2 = deployRouter(admin);
        router2.setAdapterWhitelist(pendleAdapter, true);
        router2.setAdapterWhitelist(odosAdapter, true);
        vm.stopPrank();

        uint128 debt;
        uint256 collateralAmount;
        // deal(pt_susde_may_29, borrower, collateralAmount);
        uint256 gt1 = 5;

        {
            (IERC20 ft,, IGearingToken gt, address collateral,) = mmay_30.tokens();
            (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(gt1);
            borrower = owner;
            debt = debtAmt;
            collateralAmount = abi.decode(collateralData, (uint256));
            console.log("collateralAmount:", collateralAmount);
            console.log("debt:", debt);

            vm.startPrank(borrower);
            vm.warp(may_30 - 0.5 days);

            ITermMaxOrder[] memory orders = new ITermMaxOrder[](0);
            uint128[] memory amounts = new uint128[](0);
            SwapUnit[] memory swapUnits = new SwapUnit[](2);
            address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
            swapUnits[0] = SwapUnit({
                adapter: pendleAdapter,
                tokenIn: pt_susde_may_29,
                tokenOut: susde,
                swapData: abi.encode(pm1, collateralAmount, 0)
            });
            swapUnits[1] = SwapUnit({
                adapter: odosAdapter,
                tokenIn: susde,
                tokenOut: usdc,
                swapData: hex"0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a349700000000000000000000000000000000000000000000048103daed12389fbcc800000000000000000000000076edf8c155a1e0d9b2ad11b04d9671cbc25fee99000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000005d443b21d00000000000000000000000000000000000000000000000000000005b66b4d45000000000000000000000000c47591f5c023e44931c78d5a993834875b79fb11000000000000000000000000000000000000000000000000000000000000014000000000000000000000000076edf8c155a1e0d9b2ad11b04d9671cbc25fee9900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000084010206000d0100010201022700000304000d0101050400ff00000000000000007eb59373d63627be64b42406b108b602174b4ccc9d39a5de30e57443bff2a8307a4256c8797a3497dac17f958d2ee523a2206206994597c13d831ec7c02aaa39b223fe8d0a0e5c4f27ead9083c756cc288e6a0c2ddd26feeb64f039a2c41296fcb3f564000000000000000000000000000000000000000000000000000000000"
            });

            console.log("usdc balance before:", IERC20(usdc).balanceOf(borrower));
            gt.approve(address(router2), gt1);

            SwapPath[] memory swapPaths = new SwapPath[](1);
            swapPaths[0] =
                SwapPath({units: swapUnits, recipient: address(router2), inputAmount: 0, useBalanceOnchain: true});
            bytes memory data = abi.encode(FlashRepayOptions.REPAY, abi.encode(swapPaths));
            router2.flashRepayFromCollForV1(borrower, mmay_30, gt1, true, 0, data);
            console.log("usdc balance after:", IERC20(usdc).balanceOf(borrower));
            vm.stopPrank();
        }
    }
}
