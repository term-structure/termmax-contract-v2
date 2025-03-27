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
            LiquidationBotConfig memory config = _readLiquidationBotConfig(tokenPair);
            if (config.aave.active) {
                _testLiquidate(res, config, LiquidationBot.BorrowType.AAVE, ITermMaxOrder(address(0)));
            }
        }
    }

    // function testLiquidateWithMorphoByFt() public {
    //     for (uint256 i = 0; i < tokenPairs.length; i++) {
    //         string memory tokenPair = tokenPairs[i];
    //         GtTestRes memory res = _initializeGtTestRes(tokenPair);
    //         LiquidationBotConfig memory config = _readLiquidationBotConfig(tokenPair);
    //         if (config.morpho.active) {
    //             _testLiquidate(res, config, LiquidationBot.BorrowType.MORPHO, res.order);
    //         }
    //     }
    // }

    function _testLiquidate(
        GtTestRes memory res,
        LiquidationBotConfig memory config,
        LiquidationBot.BorrowType borrowType,
        ITermMaxOrder order
    ) internal {
        {
            if (res.swapData.tokenType == TokenType.General) {
                res.swapData.leverageUnits[0].adapter = res.swapAdapters.odosAdapter;
                res.swapData.flashRepayUnits[0].adapter = res.swapAdapters.odosAdapter;
            } else if (res.swapData.tokenType == TokenType.Pendle) {
                if (res.swapData.leverageUnits.length == 1) {
                    res.swapData.leverageUnits[0].adapter = res.swapAdapters.pendleAdapter;
                    res.swapData.flashRepayUnits[0].adapter = res.swapAdapters.pendleAdapter;
                } else {
                    res.swapData.leverageUnits[1].adapter = res.swapAdapters.pendleAdapter;
                    res.swapData.leverageUnits[0].adapter = res.swapAdapters.odosAdapter;

                    res.swapData.flashRepayUnits[0].adapter = res.swapAdapters.pendleAdapter;
                    res.swapData.flashRepayUnits[1].adapter = res.swapAdapters.odosAdapter;
                }
            } else if (res.swapData.tokenType == TokenType.Morpho) {
                if (res.swapData.leverageUnits.length == 1) {
                    res.swapData.leverageUnits[0].adapter = res.swapAdapters.vaultAdapter;
                    res.swapData.flashRepayUnits[0].adapter = res.swapAdapters.vaultAdapter;
                } else {
                    res.swapData.leverageUnits[1].adapter = res.swapAdapters.vaultAdapter;
                    res.swapData.leverageUnits[0].adapter = res.swapAdapters.odosAdapter;

                    res.swapData.flashRepayUnits[0].adapter = res.swapAdapters.vaultAdapter;
                    res.swapData.flashRepayUnits[1].adapter = res.swapAdapters.odosAdapter;
                }
            }
        }
        address borrower = vm.randomAddress();

        // mint gt
        deal(borrower, 1e18);
        LiquidationBot liquidationBot = new LiquidationBot(
            IFlashLoanAave(config.aave.pool), config.aave.addressProvider, IFlashLoanMorpho(config.morpho.morpho)
        );
        uint256 gtId =
            _testLeverageFromXt(res, borrower, res.swapData.debtAmt, res.swapData.swapAmtIn, res.swapData.leverageUnits);

        // vm.warp(res.marketInitialParams.marketConfig.maturity + 1);
        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 1,
            answer: 0.5e8,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });
        vm.warp(res.marketInitialParams.marketConfig.maturity + 1);
        // vm.prank(res.marketInitialParams.admin);
        // res.collateralPriceFeed.updateRoundData(roundData);

        // roundData.answer = 1e8;
        // vm.prank(res.marketInitialParams.admin);
        // res.debtPriceFeed.updateRoundData(roundData);

        // liquidate
        address liquidator = vm.randomAddress();
        deal(liquidator, 1e18);
        vm.startPrank(liquidator);

        (, uint128 debtAmt, uint128 ltv, bytes memory collateralData) = res.gt.loanInfo(gtId);
        console.log("debtAmt:", debtAmt);
        console.log("ltv:", ltv);
        console.log("collateralData:", abi.decode(collateralData, (uint256)));

        //simulate liquidation result
        (, uint128 maxRepayAmt, uint256 cToLiquidator, uint256 incomeValue) =
            liquidationBot.simulateLiquidation(res.gt, gtId);
        console.log("simulate--maxRepayAmt:", maxRepayAmt);
        console.log("simulate--cToLiquidator:", cToLiquidator);
        console.log("simulate--incomeValue:", incomeValue);
        LiquidationBot.LiquidationParams memory liquidationParams = LiquidationBot.LiquidationParams(
            res.gt, res.debtToken, res.collateral, gtId, maxRepayAmt, res.ft, order, res.swapData.flashRepayUnits
        );
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
