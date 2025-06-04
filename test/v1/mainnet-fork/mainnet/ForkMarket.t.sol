// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../MarketBaseTest.t.sol";

contract ForkMarket is MarketBaseTest {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function testMint() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            MarketTestRes memory res = _initializeMarketTestRes(tokenPair);
            _testMint(res);
        }
    }

    function testRedeem() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            MarketTestRes memory res = _initializeMarketTestRes(tokenPair);
            _testRedeem(res);
        }
    }

    function testIssueFtByGtWhenSwap() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            MarketTestRes memory res = _initializeMarketTestRes(tokenPair);
            uint256 collateralAmt = res.orderInitialAmount / 10;
            uint128 debtAmt = uint128(res.orderInitialAmount / 100);
            _testIssueFtByGtWhenSwap(res, collateralAmt, debtAmt);
        }
    }
}
