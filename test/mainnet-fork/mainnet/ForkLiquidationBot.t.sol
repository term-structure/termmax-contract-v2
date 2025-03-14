// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../GtBaseTest.t.sol";
import {LiquidationBot, IFlashLoanAave, IFlashLoanMorpho} from "contracts/extensions/LiquidationBot.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";

contract ForkLiquidationBot is GtBaseTest {
    struct AaveConfig {
        address pool;
        address addressProvider;
        bool active;
    }

    struct MorphoConfig {
        address morpho;
        bool active;
    }

    struct LiquidationBotConfig {
        AaveConfig aave;
        MorphoConfig morpho;
    }

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function testLiquidateWithMorpho() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);
            if (!res.uniswapData.active || !res.pendleData.active) {
                continue;
            }
            LiquidationBotConfig memory config = _readLiquidationBotConfig(tokenPair);
            if (config.morpho.active) {
                _testLiquidate(res, config, LiquidationBot.BorrowType.MORPHO, ITermMaxOrder(address(0)));
            }
        }
    }

    function testTradeWithAave() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);
            if (!res.uniswapData.active || !res.pendleData.active) {
                continue;
            }
            LiquidationBotConfig memory config = _readLiquidationBotConfig(tokenPair);
            if (config.aave.active) {
                _testLiquidate(res, config, LiquidationBot.BorrowType.AAVE, ITermMaxOrder(address(0)));
            }
        }
    }

    function testLiquidateWithMorphoByFt() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);
            if (!res.uniswapData.active || !res.pendleData.active) {
                continue;
            }
            LiquidationBotConfig memory config = _readLiquidationBotConfig(tokenPair);
            if (config.morpho.active) {
                _testLiquidate(res, config, LiquidationBot.BorrowType.MORPHO, res.order);
            }
        }
    }

    function _testLiquidate(
        GtTestRes memory res,
        LiquidationBotConfig memory config,
        LiquidationBot.BorrowType borrowType,
        ITermMaxOrder order
    ) internal {
        address borrower = vm.randomAddress();

        // mint gt
        deal(borrower, 1e18);
        vm.startPrank(borrower);
        LiquidationBot liquidationBot = new LiquidationBot(
            IFlashLoanAave(config.aave.pool), config.aave.addressProvider, IFlashLoanMorpho(config.morpho.morpho)
        );
        uint256 collateralAmt = 100e8;
        uint128 debtAmt = 80e8;
        deal(address(res.collateral), borrower, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        (uint256 gtId,) = res.market.issueFt(borrower, debtAmt, abi.encode(collateralAmt));
        vm.stopPrank();

        _updateCollateralPrice(res, 0.85e8);

        // liquidate
        address liquidator = vm.randomAddress();
        deal(liquidator, 1e18);
        vm.startPrank(liquidator);
        {
            //simulate liquidation result
            (, uint128 maxRepayAmt, uint256 cToLiquidator, uint256 incomeValue) =
                liquidationBot.simulateLiquidation(res.gt, gtId);
            console.log("simulate--maxRepayAmt:", maxRepayAmt);
            console.log("simulate--cToLiquidator:", cToLiquidator);
            console.log("simulate--incomeValue:", incomeValue);
        }
        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(
            address(res.pendleData.adapter),
            res.marketInitialParams.collateral,
            res.pendleData.underlying,
            abi.encode(res.pendleData.pendleMarket, 0)
        );

        units[1] = SwapUnit(
            address(res.uniswapData.adapter),
            res.pendleData.underlying,
            address(res.marketInitialParams.debtToken),
            abi.encode(
                abi.encodePacked(
                    res.pendleData.underlying, res.uniswapData.poolFee, address(res.marketInitialParams.debtToken)
                ),
                block.timestamp + 3600,
                0
            )
        );
        LiquidationBot.LiquidationParams memory liquidationParams =
            LiquidationBot.LiquidationParams(res.gt, res.debtToken, res.collateral, gtId, debtAmt, res.ft, order, units);
        liquidationBot.liquidate(liquidationParams, borrowType);
        console.log("income:", res.debtToken.balanceOf(liquidator));
        vm.stopPrank();
    }

    function _readLiquidationBotConfig(string memory key) internal view returns (LiquidationBotConfig memory config) {
        if (vm.parseJsonBool(jsonData, string.concat(key, ".tradingBot.aave.active"))) {
            config.aave.active = true;
            config.aave.pool = vm.parseJsonAddress(jsonData, string.concat(key, ".tradingBot.aave.pool"));
            config.aave.addressProvider =
                vm.parseJsonAddress(jsonData, string.concat(key, ".tradingBot.aave.addressProvider"));
        }
        if (vm.parseJsonBool(jsonData, string.concat(key, ".tradingBot.morpho.active"))) {
            config.morpho.active = true;
            config.morpho.morpho = vm.parseJsonAddress(jsonData, string.concat(key, ".tradingBot.morpho.morpho"));
        }
    }
}
