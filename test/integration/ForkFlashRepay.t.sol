// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceFeedFactory} from "contracts/extensions/PriceFeedFactory.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {SwapUnit, ITermMaxRouter, TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {IGearingToken, GearingTokenEvents, AbstractGearingToken} from "contracts/tokens/AbstractGearingToken.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "contracts/storage/TermMaxStorage.sol";
import "test/mainnet-fork/ForkBaseTest.sol";

interface TestOracle is IOracle {
    function acceptPendingOracle(address asset) external;
    function oracles(address asset) external returns (address aggregator, address backupAggregator, uint32 heartbeat);
}

contract ForkFlashRepay is ForkBaseTest {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

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
            emit GearingTokenEvents.Repay(gt1, debt, true);
            router.flashRepayFromColl(borrower, mmay_30, gt1, orders, amounts, true, swapUnits, may_30);
            console.log("usdc balance after:", IERC20(usdc).balanceOf(borrower));
            vm.stopPrank();
        }
    }
}
