// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../MarketBaseTest.t.sol";

contract ForkMarket is MarketBaseTest {

    string envData;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function _finishSetup() internal override {
        
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

    function testIssueFtByGtWhenSwap() public{
        uint256 collateralAmt = 1e18;
        uint128 debtAmt = 1e15;
        _testIssueFtByGtWhenSwap(collateralAmt, debtAmt);
    }
}