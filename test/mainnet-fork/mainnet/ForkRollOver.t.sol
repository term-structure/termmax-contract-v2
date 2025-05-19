// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../ForkBaseTest.sol";
import {PriceFeedFactory} from "contracts/extensions/PriceFeedFactory.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {SwapUnit, ITermMaxRouter, TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {IGearingToken, GearingTokenEvents, AbstractGearingToken} from "contracts/tokens/AbstractGearingToken.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "contracts/storage/TermMaxStorage.sol";

interface TestOracle is IOracle {
    function acceptPendingOracle(address asset) external;
    function oracles(address asset) external returns (address aggregator, address backupAggregator, uint32 heartbeat);
}

contract ForkRollOver is ForkBaseTest {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function testRolloverPt() public {
        vm.roll(22486319); // 2025-05-15
        uint64 may_30 = 1748534400; // 2025-05-30 00:00:00
        uint64 aug_1 = 1753977600; // 2025-08-01 00:00:00
        address pt_susde_may_29 = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
        address pt_susde_jun_31 = 0x3b3fB9C57858EF816833dC91565EFcd85D96f634;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        address susde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        TestOracle oracle = TestOracle(0xE3a31690392E8E18DC3d862651C079339E2c1ADE);
        address accessManager = Ownable(address(oracle)).owner();
        vm.startPrank(accessManager);
        address[] memory tokens = new address[](4);
        tokens[0] = usdc;
        tokens[1] = susde;
        tokens[2] = pt_susde_may_29;
        tokens[3] = pt_susde_jun_31;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            (address aggregator, address backupAggregator, uint32 heartbeat) = oracle.oracles(token);
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

        // ITermMaxRouter router = ITermMaxRouter(0xC47591F5c023e44931c78D5A993834875b79FB11);
        ITermMaxMarket mmay_30 = ITermMaxMarket(0xe867255dC0c3a27c90f756ECC566a5292ce19492);
        ITermMaxMarket maug_1 = ITermMaxMarket(0xdBB2D44c238c459cCB820De886ABF721EF6E6941);
        ITermMaxOrder o_may_30 = ITermMaxOrder(0xe99ee5b18cB57276EbEADf0E773E4f8Ab49Db9B7);
        ITermMaxOrder o_aug_1 = ITermMaxOrder(0x71Df74d65c3895C8FA5a1c8E8d93A7eE30A1aFc7);

        {
            address yt = 0x1de6Ff19FDA7496DdC12f2161f6ad6427c52aBBe;
            deal(yt, pt_susde_may_29, 1000 ether);
        }

        // address pendleAdapter = 0x0B30251FA697A39Fd41813b267b50F03414E82da;
        PendleSwapV3Adapter adapter = new PendleSwapV3Adapter(0x888888888889758F76e7103c6CbF23ABbF58F946);
        address pendleAdapter = address(adapter);

        vm.label(pt_susde_may_29, "pt_susde_may_29");
        vm.label(pt_susde_jun_31, "pt_susde_jun_31");
        vm.label(susde, "susde");
        vm.label(address(oracle), "oracle");
        vm.label(address(mmay_30), "mmay_30");
        vm.label(address(maug_1), "maug_1");
        vm.label(address(o_may_30), "o_may_30");
        vm.label(address(o_aug_1), "o_aug_1");
        vm.label(address(pendleAdapter), "pendleAdapter");

        address borrower;
        address admin = vm.randomAddress();

        vm.startPrank(admin);
        TermMaxRouter router = deployRouter(admin);
        router.setAdapterWhitelist(pendleAdapter, true);
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

            uint128 repayAmount = debt / 10;

            ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
            orders[0] = ITermMaxOrder(address(o_aug_1));
            uint128[] memory amounts = new uint128[](1);
            amounts[0] = debt - repayAmount;
            (IERC20 ft,, IGearingToken gt, address collateral,) = mmay_30.tokens();

            deal(usdc, borrower, repayAmount);
            IERC20(usdc).approve(address(router), repayAmount);
            gt.approve(address(router), gt1);

            (IERC20 ft_aug_1,,,,) = maug_1.tokens();
            ITermMaxRouter.TermMaxSwapData memory swapData = ITermMaxRouter.TermMaxSwapData({
                tokenIn: address(ft_aug_1),
                tokenOut: usdc,
                orders: orders,
                tradingAmts: amounts,
                netTokenAmt: debt,
                deadline: aug_1
            });
            uint256 gtId2 = router.rolloverGt(borrower, gt, gt1, 0.9e8, repayAmount, maug_1, swapUnits, swapData);
            console.log("new gtId:", gtId2);
        }

        vm.stopPrank();
    }

    function testFlashRepayPt() public {
        vm.roll(22494579); // 2025-05-15
        uint64 may_30 = 1748534400; // 2025-05-30 00:00:00
        address pt_susde_may_29 = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        address susde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        TestOracle oracle = TestOracle(0xE3a31690392E8E18DC3d862651C079339E2c1ADE);
        address accessManager = Ownable(address(oracle)).owner();
        vm.startPrank(accessManager);
        address[] memory tokens = new address[](3);
        tokens[0] = usdc;
        tokens[1] = susde;
        tokens[2] = pt_susde_may_29;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            (address aggregator, address backupAggregator, uint32 heartbeat) = oracle.oracles(token);
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

        ITermMaxMarket mmay_30 = ITermMaxMarket(0xe867255dC0c3a27c90f756ECC566a5292ce19492);
        ITermMaxOrder o_may_30 = ITermMaxOrder(0xe99ee5b18cB57276EbEADf0E773E4f8Ab49Db9B7);

        {
            address yt = 0x1de6Ff19FDA7496DdC12f2161f6ad6427c52aBBe;
            deal(yt, pt_susde_may_29, 1000 ether);
        }

        // address pendleAdapter = 0x0B30251FA697A39Fd41813b267b50F03414E82da;
        PendleSwapV3Adapter adapter = new PendleSwapV3Adapter(0x888888888889758F76e7103c6CbF23ABbF58F946);
        address pendleAdapter = address(adapter);

        vm.label(pt_susde_may_29, "pt_susde_may_29");
        vm.label(susde, "susde");
        vm.label(address(oracle), "oracle");
        vm.label(address(mmay_30), "mmay_30");
        vm.label(address(o_may_30), "o_may_30");
        vm.label(address(pendleAdapter), "pendleAdapter");

        address borrower;
        address admin = vm.randomAddress();

        vm.startPrank(admin);
        TermMaxRouter router = deployRouter(admin);
        router.setAdapterWhitelist(pendleAdapter, true);
        router.setAdapterWhitelist(0x2aFEf28a8Ab57d2F5A5663Ef69351e9d3abf1779, true);
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
                adapter: 0x2aFEf28a8Ab57d2F5A5663Ef69351e9d3abf1779,
                tokenIn: susde,
                tokenOut: usdc,
                swapData: hex"0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a349700000000000000000000000000000000000000000000048103daed12389fbcc800000000000000000000000076edf8c155a1e0d9b2ad11b04d9671cbc25fee99000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000005d443b21d00000000000000000000000000000000000000000000000000000005b66b4d45000000000000000000000000c47591f5c023e44931c78d5a993834875b79fb11000000000000000000000000000000000000000000000000000000000000014000000000000000000000000076edf8c155a1e0d9b2ad11b04d9671cbc25fee9900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000084010206000d0100010201022700000304000d0101050400ff00000000000000007eb59373d63627be64b42406b108b602174b4ccc9d39a5de30e57443bff2a8307a4256c8797a3497dac17f958d2ee523a2206206994597c13d831ec7c02aaa39b223fe8d0a0e5c4f27ead9083c756cc288e6a0c2ddd26feeb64f039a2c41296fcb3f564000000000000000000000000000000000000000000000000000000000"
            });

            console.log("usdc balance before:", IERC20(usdc).balanceOf(borrower));
            gt.approve(address(router), gt1);
            vm.expectEmit();
            emit GearingTokenEvents.FlashRepay(gt1, address(router), debt, true, true, abi.encode(collateralAmount));
            router.flashRepayFromColl(borrower, mmay_30, gt1, orders, amounts, true, swapUnits, may_30);
            console.log("usdc balance after:", IERC20(usdc).balanceOf(borrower));
            vm.stopPrank();
        }
    }
}
