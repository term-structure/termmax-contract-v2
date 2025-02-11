// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../GtBaseTest.t.sol";

contract ForkGt is GtBaseTest {

    string envData;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function _finishSetup() internal override {
        uniswapAdapter = new UniswapV3Adapter(vm.parseJsonAddress(envData, ".routers.uniswap.address"));
        pendleAdapter = new PendleSwapV3Adapter(vm.parseJsonAddress(envData, ".routers.pendle.address"));
        odosAdapter = new OdosV2Adapter(vm.parseJsonAddress(envData, ".routers.odos.address"));

        vm.startPrank(marketInitialParams.admin);
        router.setAdapterWhitelist(address(uniswapAdapter), true);
        router.setAdapterWhitelist(address(pendleAdapter), true);
        router.setAdapterWhitelist(address(odosAdapter), true);
        vm.stopPrank();
    }

    function _getEnv() internal override returns (EnvConfig memory env) {
        envData = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json"));
        env.forkRpcUrl = MAINNET_RPC_URL;
        env.forkBlockNumber = vm.parseUint(vm.parseJsonString(envData, ".blockNumber"));
        env.extraData = abi.encode(_readMarketInitialParams(), _readOrderConfig().curveCuts);
        return env;
    }

    function _readMarketInitialParams() internal returns (MarketInitialParams memory marketInitialParams) {
        marketInitialParams.admin = vm.randomAddress();
        marketInitialParams.collateral = vm.parseJsonAddress(envData, ".collateral");
        marketInitialParams.debtToken = IERC20Metadata(vm.parseJsonAddress(envData, ".debtToken"));

        marketInitialParams.tokenName = "PTWEETH-WETH";
        marketInitialParams.tokenSymbol = "PTWEETH-WETH";

        MarketConfig memory marketConfig;
        marketConfig.feeConfig.redeemFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(envData, ".feeConfig.redeemFeeRatio")));
        marketConfig.feeConfig.issueFtFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(envData, ".feeConfig.issueFtFeeRatio")));
        marketConfig.feeConfig.issueFtFeeRef =
            uint32(vm.parseUint(vm.parseJsonString(envData, ".feeConfig.issueFtFeeRef")));
        marketConfig.feeConfig.lendTakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(envData, ".feeConfig.lendTakerFeeRatio")));
        marketConfig.feeConfig.borrowTakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(envData, ".feeConfig.borrowTakerFeeRatio")));
        marketConfig.feeConfig.lendMakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(envData, ".feeConfig.lendMakerFeeRatio")));
        marketConfig.feeConfig.borrowMakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(envData, ".feeConfig.borrowMakerFeeRatio")));
        marketInitialParams.marketConfig = marketConfig;

        marketConfig.treasurer = vm.randomAddress();
        marketConfig.maturity = uint64(86400 * vm.parseUint(vm.parseJsonString(envData, ".duration")));

        marketInitialParams.loanConfig.maxLtv =
            uint32(vm.parseUint(vm.parseJsonString(envData, ".loanConfig.maxLtv")));
        marketInitialParams.loanConfig.liquidationLtv =
            uint32(vm.parseUint(vm.parseJsonString(envData, ".loanConfig.liquidationLtv")));
        marketInitialParams.loanConfig.liquidatable =
            vm.parseBool(vm.parseJsonString(envData, ".loanConfig.liquidatable"));

        marketInitialParams.gtInitalParams = abi.encode(type(uint256).max);
        
        return marketInitialParams;
    }

    function _readOrderConfig() internal view returns (OrderConfig memory orderConfig) {
        orderConfig = JSONLoader.getOrderConfigFromJson(envData, ".orderConfig");
        return orderConfig;
    }

    function testBorrow() public{
        uint256 collateralAmt = 1e18;
        uint128 borrowAmt = 10000e8;
        uint128 maxDebtAmt = 15000e8;
        _testBorrow(collateralAmt, borrowAmt, maxDebtAmt);
    }

    function testLeverageFromXtWithUniswap() public {
        address taker = vm.randomAddress();
        uint128 xtAmtIn = 10000e8;
        uint128 tokenAmtIn = 1e15;

        uint24 poolFee = uint24(vm.parseUint(vm.parseJsonString(envData, ".routers.uniswap.poolFee")));
        address ptUnderlying = vm.parseJsonAddress(envData, ".routers.pendle.underlying");
        address ptMarket = vm.parseJsonAddress(envData, ".routers.pendle.market");

        SwapUnit[] memory units = new SwapUnit[](2);
        
        units[0] = SwapUnit(
            address(uniswapAdapter),
            address(marketInitialParams.debtToken),
            ptUnderlying,
            abi.encode(abi.encodePacked(address(marketInitialParams.debtToken), poolFee, ptUnderlying), block.timestamp + 3600, 0)
        );
        units[1] = SwapUnit(address(pendleAdapter), ptUnderlying, marketInitialParams.collateral, abi.encode(ptMarket, 0));

        _testLeverageFromXt(
            taker,
            xtAmtIn,
            tokenAmtIn,
            units
        );
    }

    function testLeverageFromXtWithPendle() public {
        address taker = vm.randomAddress();
        uint128 xtAmtIn = 10000e8;
        uint128 tokenAmtIn = 10e18;

        address ptUnderlying = vm.parseJsonAddress(envData, ".routers.pendle.underlying");
        address ptMarket = vm.parseJsonAddress(envData, ".routers.pendle.market");

        // Note: reference Odos docs: https://docs.odos.xyz/build/api-docs
        address odosInputReceiver = vm.parseJsonAddress(envData, ".routers.odos.odosInputReceiver"); // Curve pool weETH/WETH
        uint256 outputQuote = vm.parseUint(vm.parseJsonString(envData, ".routers.odos.outputQuote"));
        uint256 outputMin = vm.parseUint(vm.parseJsonString(envData, ".routers.odos.outputMin"));
        IOdosRouterV2.swapTokenInfo memory swapTokenInfoParam = IOdosRouterV2.swapTokenInfo(
            address(marketInitialParams.debtToken),
            tokenAmtIn,
            address(odosInputReceiver),
            address(ptUnderlying),
            outputQuote,
            outputMin,
            address(router)
        );
        address odosExecutor = vm.parseJsonAddress(envData, ".routers.odos.odosExecutor");
        bytes memory odosPath = vm.parseJsonBytes(envData, ".routers.odos.odosPath");
        uint32 odosReferralCode = uint32(vm.parseUint(vm.parseJsonString(envData, ".routers.odos.odosReferralCode")));
        bytes memory odosSwapData = abi.encode(swapTokenInfoParam, odosPath, odosExecutor, odosReferralCode);

        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(
            address(odosAdapter),
            address(marketInitialParams.debtToken),
            ptUnderlying,
            odosSwapData
        );
        units[1] = SwapUnit(address(pendleAdapter), ptUnderlying, marketInitialParams.collateral, abi.encode(ptMarket, 0));

        _testLeverageFromXt(
            taker,
            xtAmtIn,
            tokenAmtIn,
            units
        );
    }

    function testFlashRepay() public {
        address taker = vm.randomAddress();

        uint128 debtAmt = 10000e8;
        uint128 collateralAmt = 15000e8;
        uint256 gtId = _fastLoan(taker, debtAmt, collateralAmt);

        uint24 poolFee = uint24(vm.parseUint(vm.parseJsonString(envData, ".routers.uniswap.poolFee")));
        address ptUnderlying = vm.parseJsonAddress(envData, ".routers.pendle.underlying");
        address ptMarket = vm.parseJsonAddress(envData, ".routers.pendle.market");

        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(address(pendleAdapter), marketInitialParams.collateral, ptUnderlying, abi.encode(ptMarket, 0));

        units[1] = SwapUnit(
            address(uniswapAdapter),
            ptUnderlying,
            address(marketInitialParams.debtToken),
            abi.encode(abi.encodePacked(ptUnderlying, poolFee, address(marketInitialParams.debtToken)), block.timestamp + 3600, 0)
        );

        _testFlashRepay(gtId, taker, units);
    }

    function testFlashRepayByFt() public {
        address taker = vm.randomAddress();

        uint128 debtAmt = 10000e8;
        uint128 collateralAmt = 15000e8;
        uint256 gtId = _fastLoan(taker, debtAmt, collateralAmt);

        uint24 poolFee = uint24(vm.parseUint(vm.parseJsonString(envData, ".routers.uniswap.poolFee")));
        address ptUnderlying = vm.parseJsonAddress(envData, ".routers.pendle.underlying");
        address ptMarket = vm.parseJsonAddress(envData, ".routers.pendle.market");

        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(address(pendleAdapter), marketInitialParams.collateral, ptUnderlying, abi.encode(ptMarket, 0));

        units[1] = SwapUnit(
            address(uniswapAdapter),
            ptUnderlying,
            address(marketInitialParams.debtToken),
            abi.encode(abi.encodePacked(ptUnderlying, poolFee, address(marketInitialParams.debtToken)), block.timestamp + 3600, 0)
        );

        _testFlashRepayByFt(gtId, debtAmt, taker, units);
    }

    function testLiquidate() public {
        address liquidator = vm.randomAddress();
        address borrower = vm.randomAddress();
        // ltv = 2000 * 0.8 / 1800
        uint256 gtId = _fastLoan(borrower, 0.8e18, 1e18);
        vm.startPrank(marketInitialParams.admin);
        // update oracle
        collateralPriceFeed.updateRoundData(
            JSONLoader.getRoundDataFromJson(envData, ".priceData.ETH_2000_PT_WEETH_1000.ptWeeth")
        );
        debtPriceFeed.updateRoundData(
            JSONLoader.getRoundDataFromJson(envData, ".priceData.ETH_2000_PT_WEETH_1000.eth")
        );
        vm.stopPrank();
        _testLiquidate(liquidator, gtId);
    }

}