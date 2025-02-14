// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../GtBaseTest.t.sol";

contract ForkGt is GtBaseTest {

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

    function testLeverageFromXtWithUniswapAndPendle() public {
        for(uint256 i = 0; i < tokenPairs.length; i++){
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);
            if(!res.uniswapData.active || !res.pendleData.active){
                continue;
            }
            address taker = vm.randomAddress();

            SwapUnit[] memory units = new SwapUnit[](2);
        
            units[0] = SwapUnit(
                address(res.uniswapData.adapter),
                address(res.marketInitialParams.debtToken),
                res.pendleData.underlying,
                abi.encode(abi.encodePacked(address(res.marketInitialParams.debtToken), res.uniswapData.poolFee, res.pendleData.underlying), block.timestamp + 3600, 0)
            );
            units[1] = SwapUnit(address(res.pendleData.adapter), res.pendleData.underlying, res.marketInitialParams.collateral, abi.encode(res.pendleData.pendleMarket, 0));

            _testLeverageFromXt(
                res,
                taker,
                res.uniswapData.leverageAmountData.debtAmt,
                res.uniswapData.leverageAmountData.swapAmtIn,
                units
            );
        }
    }


    function testLeverageFromXtWithOdosAndPendle() public {
        for(uint256 i = 0; i < tokenPairs.length; i++){
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);
            if(!res.odosData.active || !res.pendleData.active){
                continue;
            }
            address taker = vm.randomAddress();

            // Note: reference Odos docs: https://docs.odos.xyz/build/api-docs
            IOdosRouterV2.swapTokenInfo memory swapTokenInfoParam = IOdosRouterV2.swapTokenInfo(
                address(res.marketInitialParams.debtToken),
                res.odosData.leverageAmountData.swapAmtIn,
                res.odosData.odosInputReceiver,
                res.pendleData.underlying,
                res.odosData.outputQuote,
                res.odosData.outputMin,
                res.odosData.router
            );
            bytes memory odosSwapData = abi.encode(swapTokenInfoParam, res.odosData.odosPath, res.odosData.odosExecutor, res.odosData.odosReferralCode);

            SwapUnit[] memory units = new SwapUnit[](2);
        
            units[0] = SwapUnit(
                address(res.odosData.adapter),
                address(res.marketInitialParams.debtToken),
                res.pendleData.underlying,
                odosSwapData
            );
            units[1] = SwapUnit(address(res.pendleData.adapter), res.pendleData.underlying, res.marketInitialParams.collateral, abi.encode(res.pendleData.pendleMarket, 0));

            _testLeverageFromXt(
                res,
                taker,
                res.odosData.leverageAmountData.debtAmt,
                res.odosData.leverageAmountData.swapAmtIn,
                units
            );
        }
    }

    function testFashRepayWithUniswapAndPendle() public {
        for(uint256 i = 0; i < tokenPairs.length; i++){ 
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);
            if(!res.uniswapData.active || !res.pendleData.active){
                continue;
            }
            address taker = vm.randomAddress();

            uint128 debtAmt = uint128(res.orderInitialAmount/20);
            uint128 collateralAmt = uint128(res.orderInitialAmount/10);
            uint256 gtId = _fastLoan(res, taker, debtAmt, collateralAmt);

            SwapUnit[] memory units = new SwapUnit[](2);
             units[0] = SwapUnit(address(res.pendleData.adapter),
              res.marketInitialParams.collateral, 
              res.pendleData.underlying, 
              abi.encode(res.pendleData.pendleMarket, 0));

            units[1] = SwapUnit(
                address(res.uniswapData.adapter),
                res.pendleData.underlying,
                address(res.marketInitialParams.debtToken),
                abi.encode(abi.encodePacked(res.pendleData.underlying, res.uniswapData.poolFee, address(res.marketInitialParams.debtToken)), block.timestamp + 3600, 0)
            );

            _testFlashRepay(res, gtId, taker, units);
        }
    }

    function testFashRepayByFtWithUniswapAndPendle() public {
        for(uint256 i = 0; i < tokenPairs.length; i++){ 
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);
            if(!res.uniswapData.active || !res.pendleData.active){
                continue;
            }
            address taker = vm.randomAddress();

            uint128 debtAmt = uint128(res.orderInitialAmount/20);
            uint128 collateralAmt = uint128(res.orderInitialAmount/10);
            uint256 gtId = _fastLoan(res, taker, debtAmt, collateralAmt);

            SwapUnit[] memory units = new SwapUnit[](2);
             units[0] = SwapUnit(address(res.pendleData.adapter),
              res.marketInitialParams.collateral, 
              res.pendleData.underlying, 
              abi.encode(res.pendleData.pendleMarket, 0));

            units[1] = SwapUnit(
                address(res.uniswapData.adapter),
                res.pendleData.underlying,
                address(res.marketInitialParams.debtToken),
                abi.encode(abi.encodePacked(res.pendleData.underlying, res.uniswapData.poolFee, address(res.marketInitialParams.debtToken)), block.timestamp + 3600, 0)
            );
            _testFlashRepayByFt(res, gtId, debtAmt, taker, units);
        }
    }

    function testLiquidate() public {

        for(uint256 i = 0; i < tokenPairs.length; i++){
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);

            address liquidator = vm.randomAddress();
            address borrower = vm.randomAddress();

            uint256 collateralAmt = res.orderInitialAmount/10;
            uint128 borrowAmt = uint128(res.orderInitialAmount/20);

            uint256 gtId = _fastLoan(res, borrower, borrowAmt, collateralAmt);
            _updateCollateralPrice(res, 0.5e8);

            _testLiquidate(res, liquidator, gtId);
        }
    }

}