// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../GtBaseTest.t.sol";

contract ForkGtV1 is GtBaseTest {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/bsc.json");

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function testBorrow() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);
            uint256 collateralAmt = res.orderInitialAmount / 10;
            uint128 borrowAmt = uint128(res.orderInitialAmount / 30);
            uint128 maxDebtAmt = uint128(res.orderInitialAmount / 20);
            _testBorrow(res, collateralAmt, borrowAmt, maxDebtAmt);
        }
    }

    function testLeverageFromXt() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);

            address taker = vm.randomAddress();

            _testLeverageFromXt(res, taker, res.swapData.debtAmt, res.swapData.swapAmtIn, res.swapData.leverageUnits);
        }
    }

    function testFlashRepay() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);

            address taker = vm.randomAddress();
            uint256 gtId = _testLeverageFromXt(
                res, taker, res.swapData.debtAmt, res.swapData.swapAmtIn, res.swapData.leverageUnits
            );
            _testFlashRepay(res, gtId, taker, res.swapData.flashRepayUnits);
        }
    }

    function testFlashRepayByFt() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);

            address taker = vm.randomAddress();
            uint256 gtId = _testLeverageFromXt(
                res, taker, res.swapData.debtAmt, res.swapData.swapAmtIn, res.swapData.leverageUnits
            );
            _testFlashRepayByFt(res, gtId, taker, res.swapData.flashRepayUnits);
        }
    }

    function testLiquidate() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            GtTestRes memory res = _initializeGtTestRes(tokenPair);

            address liquidator = vm.randomAddress();
            address borrower = vm.randomAddress();

            uint256 collateralAmt = res.orderInitialAmount / 10;
            uint128 borrowAmt = uint128(res.orderInitialAmount / 20);

            uint256 gtId = _fastLoan(res, borrower, borrowAmt, collateralAmt);
            _updateCollateralPrice(res, 1);

            _testLiquidate(res, liquidator, gtId);
        }
    }
}
