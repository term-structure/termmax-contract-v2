// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../GtBaseTest.t.sol";

contract ForkGt is GtBaseTest {

    string envData;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    function _getForkRpcUrl() internal view override returns (string memory){
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory){
        return DATA_PATH;
    }

    function _finishSetup() internal override{

    }

    function testBorrow() public{
        for(uint256 i = 0; i < tokenPairs.length; i++){
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);
            uint256 collateralAmt = res.orderInitialAmount/10;
            uint128 borrowAmt = uint128(res.orderInitialAmount/30);
            uint128 maxDebtAmt = uint128(res.orderInitialAmount/20);
            _testBorrow(res, collateralAmt, borrowAmt, maxDebtAmt);
        }
    }

    // function testBorrow() public{
    //     uint256 collateralAmt = 1e18;
    //     uint128 borrowAmt = 0.01e18;
    //     uint128 maxDebtAmt = 0.03e18;
    //     _testBorrow(collateralAmt, borrowAmt, maxDebtAmt);
    // }

    // function testLeverageFromXtWithUniswap() public {
    //     address taker = vm.randomAddress();
    //     uint128 xtAmtIn = 0.01e18;
    //     uint128 tokenAmtIn = 1e18;

    //     uint24 poolFee = uint24(vm.parseUint(vm.parseJsonString(envData, ".routers.uniswap.poolFee")));
    //     address ptUnderlying = vm.parseJsonAddress(envData, ".routers.pendle.underlying");
    //     address ptMarket = vm.parseJsonAddress(envData, ".routers.pendle.market");

    //     SwapUnit[] memory units = new SwapUnit[](2);
        
    //     units[0] = SwapUnit(
    //         address(uniswapAdapter),
    //         address(marketInitialParams.debtToken),
    //         ptUnderlying,
    //         abi.encode(abi.encodePacked(address(marketInitialParams.debtToken), poolFee, ptUnderlying), block.timestamp + 3600, 0)
    //     );
    //     units[1] = SwapUnit(address(pendleAdapter), ptUnderlying, marketInitialParams.collateral, abi.encode(ptMarket, 0));

    //     _testLeverageFromXt(
    //         taker,
    //         xtAmtIn,
    //         tokenAmtIn,
    //         units
    //     );
    // }

    // function testLeverageFromXtWithPendle() public {
    //     address taker = vm.randomAddress();
    //     uint128 xtAmtIn = 0.01e18;
    //     uint128 tokenAmtIn = 10e18;

    //     address ptUnderlying = vm.parseJsonAddress(envData, ".routers.pendle.underlying");
    //     address ptMarket = vm.parseJsonAddress(envData, ".routers.pendle.market");

    //     // Note: reference Odos docs: https://docs.odos.xyz/build/api-docs
    //     address odosInputReceiver = vm.parseJsonAddress(envData, ".routers.odos.odosInputReceiver"); // Curve pool weETH/WETH
    //     uint256 outputQuote = vm.parseUint(vm.parseJsonString(envData, ".routers.odos.outputQuote"));
    //     uint256 outputMin = vm.parseUint(vm.parseJsonString(envData, ".routers.odos.outputMin"));
    //     IOdosRouterV2.swapTokenInfo memory swapTokenInfoParam = IOdosRouterV2.swapTokenInfo(
    //         address(marketInitialParams.debtToken),
    //         tokenAmtIn,
    //         address(odosInputReceiver),
    //         address(ptUnderlying),
    //         outputQuote,
    //         outputMin,
    //         address(router)
    //     );
    //     address odosExecutor = vm.parseJsonAddress(envData, ".routers.odos.odosExecutor");
    //     bytes memory odosPath = vm.parseJsonBytes(envData, ".routers.odos.odosPath");
    //     uint32 odosReferralCode = uint32(vm.parseUint(vm.parseJsonString(envData, ".routers.odos.odosReferralCode")));
    //     bytes memory odosSwapData = abi.encode(swapTokenInfoParam, odosPath, odosExecutor, odosReferralCode);

    //     SwapUnit[] memory units = new SwapUnit[](2);
    //     units[0] = SwapUnit(
    //         address(odosAdapter),
    //         address(marketInitialParams.debtToken),
    //         ptUnderlying,
    //         odosSwapData
    //     );
    //     units[1] = SwapUnit(address(pendleAdapter), ptUnderlying, marketInitialParams.collateral, abi.encode(ptMarket, 0));

    //     _testLeverageFromXt(
    //         taker,
    //         xtAmtIn,
    //         tokenAmtIn,
    //         units
    //     );
    // }

    // function testFlashRepay() public {
    //     address taker = vm.randomAddress();

    //     uint128 debtAmt = 0.01e18;
    //     uint128 collateralAmt = 1e18;
    //     uint256 gtId = _fastLoan(taker, debtAmt, collateralAmt);

    //     uint24 poolFee = uint24(vm.parseUint(vm.parseJsonString(envData, ".routers.uniswap.poolFee")));
    //     address ptUnderlying = vm.parseJsonAddress(envData, ".routers.pendle.underlying");
    //     address ptMarket = vm.parseJsonAddress(envData, ".routers.pendle.market");

    //     SwapUnit[] memory units = new SwapUnit[](2);
    //     units[0] = SwapUnit(address(pendleAdapter), marketInitialParams.collateral, ptUnderlying, abi.encode(ptMarket, 0));

    //     units[1] = SwapUnit(
    //         address(uniswapAdapter),
    //         ptUnderlying,
    //         address(marketInitialParams.debtToken),
    //         abi.encode(abi.encodePacked(ptUnderlying, poolFee, address(marketInitialParams.debtToken)), block.timestamp + 3600, 0)
    //     );

    //     _testFlashRepay(gtId, taker, units);
    // }

    // function testFlashRepayByFt() public {
    //     address taker = vm.randomAddress();

    //     uint128 debtAmt = 0.01e18;
    //     uint128 collateralAmt = 1e18;
    //     uint256 gtId = _fastLoan(taker, debtAmt, collateralAmt);

    //     uint24 poolFee = uint24(vm.parseUint(vm.parseJsonString(envData, ".routers.uniswap.poolFee")));
    //     address ptUnderlying = vm.parseJsonAddress(envData, ".routers.pendle.underlying");
    //     address ptMarket = vm.parseJsonAddress(envData, ".routers.pendle.market");

    //     SwapUnit[] memory units = new SwapUnit[](2);
    //     units[0] = SwapUnit(address(pendleAdapter), marketInitialParams.collateral, ptUnderlying, abi.encode(ptMarket, 0));

    //     units[1] = SwapUnit(
    //         address(uniswapAdapter),
    //         ptUnderlying,
    //         address(marketInitialParams.debtToken),
    //         abi.encode(abi.encodePacked(ptUnderlying, poolFee, address(marketInitialParams.debtToken)), block.timestamp + 3600, 0)
    //     );

    //     _testFlashRepayByFt(gtId, debtAmt, taker, units);
    // }

    // function testLiquidate() public {
    //     address liquidator = vm.randomAddress();
    //     address borrower = vm.randomAddress();
    //     // ltv = 2000 * 0.08 / 1800 * 0.1
    //     uint256 gtId = _fastLoan(borrower, 0.8e17, 1e17);
    //     vm.startPrank(marketInitialParams.admin);
    //     // update oracle
    //     collateralPriceFeed.updateRoundData(
    //         JSONLoader.getRoundDataFromJson(envData, ".priceData.ETH_2000_PT_WEETH_1000.ptWeeth")
    //     );
    //     debtPriceFeed.updateRoundData(
    //         JSONLoader.getRoundDataFromJson(envData, ".priceData.ETH_2000_PT_WEETH_1000.eth")
    //     );
    //     vm.stopPrank();
    //     _testLiquidate(liquidator, gtId);
    // }

}