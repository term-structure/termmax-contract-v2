// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../MarketBaseTest.t.sol";
import {TradingBot, IFlashLoanAave, IFlashLoanMorpho} from "contracts/extensions/TradingBot.sol";

contract ForkTradingBot is MarketBaseTest {
    struct AaveConfig {
        address pool;
        address addressProvider;
        bool active;
    }

    struct MorphoConfig {
        address morpho;
        bool active;
    }

    struct TradingBotConfig {
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

    function testTradeWithMorpho() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            MarketTestRes memory res = _initializeMarketTestRes(tokenPair);
            TradingBotConfig memory config = _readTradingBotConfig(tokenPair);
            if (config.morpho.active) {
                _testTradingBot(res, config, TradingBot.BorrowType.MORPHO);
            }
        }
    }

    function testTradeWithAave() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            MarketTestRes memory res = _initializeMarketTestRes(tokenPair);
            TradingBotConfig memory config = _readTradingBotConfig(tokenPair);
            if (config.aave.active) {
                _testTradingBot(res, config, TradingBot.BorrowType.AAVE);
            }
        }
    }

    function _testTradingBot(MarketTestRes memory res, TradingBotConfig memory config, TradingBot.BorrowType borrowType)
        internal
    {
        // deploy trading bot and create order2
        address maker2 = vm.randomAddress();
        deal(maker2, 1e18);
        vm.startPrank(maker2);
        TradingBot tradingBot = new TradingBot(
            IFlashLoanAave(config.aave.pool),
            config.aave.addressProvider,
            IFlashLoanMorpho(config.morpho.morpho),
            res.router
        );
        ITermMaxOrder order2 =
            res.market.createOrder(maker2, res.maxXtReserve, ISwapCallback(address(0)), res.orderConfig.curveCuts);
        uint128 amount = uint128(res.orderInitialAmount / 100);
        deal(address(res.debtToken), maker2, amount);
        res.debtToken.approve(address(res.market), amount);
        res.market.mint(address(order2), amount);
        vm.stopPrank();

        ITermMaxOrder[] memory buyOrders = new ITermMaxOrder[](1);
        buyOrders[0] = order2;
        uint128[] memory tradingAmts = new uint128[](1);
        tradingAmts[0] = amount;

        ITermMaxOrder[] memory sellOrders = new ITermMaxOrder[](1);
        sellOrders[0] = res.order;

        address recipent = vm.randomAddress();
        uint256 minIncome = 1;
        IERC20 tradeToken = res.ft;
        deal(recipent, 1e18);
        vm.startPrank(recipent);
        tradingBot.doTrade(
            address(res.debtToken),
            tradingAmts[0],
            borrowType,
            abi.encode(minIncome, tradeToken, recipent, buyOrders, sellOrders, tradingAmts)
        );
        vm.stopPrank();
    }

    function _readTradingBotConfig(string memory key) internal view returns (TradingBotConfig memory config) {
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
