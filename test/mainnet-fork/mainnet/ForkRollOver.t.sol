// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../ForkBaseTest.sol";
import {PriceFeedFactory} from "contracts/extensions/PriceFeedFactory.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";

contract ForkRollOver is ForkBaseTest {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function testRolloverPt() public {
        vm.roll(22486319); // 2025-08-01 00:00:00
        uint64 may_30 = 1748534400; // 2025-05-30 00:00:00
        uint64 aug_1 = 1753977600; // 2025-08-01 00:00:00
        address pt_susde_may_29 = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
        address pt_susde_jun_31 = 0x3b3fB9C57858EF816833dC91565EFcd85D96f634;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        IOracle oracle = IOracle(0xE3a31690392E8E18DC3d862651C079339E2c1ADE);
        ITermMaxRouter router = ITermMaxRouter(0xC47591F5c023e44931c78D5A993834875b79FB11);
        ITermMaxMarket mmay_30 = ITermMaxMarket(0xe867255dC0c3a27c90f756ECC566a5292ce19492);
        ITermMaxMarket maug_1 = ITermMaxMarket(0xdBB2D44c238c459cCB820De886ABF721EF6E6941);
        string memory key = "sUSDe-USDC";
        OrderConfig memory orderConfig = _readOrderConfig(key);
        MarketInitialParams memory marketInitialParams = _readMarketInitialParams(key);
        marketInitialParams.collateral = pt_susde_may_29;
        marketInitialParams.marketConfig.maturity = may_30; // 2025-05-30 00:00:00
        marketInitialParams.loanConfig.oracle = oracle;

        address borrower = vm.randomAddress();
        address admin = vm.randomAddress();

        bytes32 GT_ERC20 = keccak256("GearingTokenWithERC20");

        TermMaxFactory termMaxFactory = deployFactory(admin);
        vm.startPrank(admin);
        ITermMaxMarket m1 = ITermMaxMarket(termMaxFactory.createMarket(GT_ERC20, marketInitialParams, 0));

        marketInitialParams.collateral = pt_susde_jun_31;
        marketInitialParams.marketConfig.maturity = aug_1; // 2025-08-01 00:00:00
        marketInitialParams.loanConfig.oracle = oracle;

        ITermMaxMarket m2 = ITermMaxMarket(termMaxFactory.createMarket(GT_ERC20, marketInitialParams, 0));

        ITermMaxOrder o1 = m1.createOrder(orderConfig, borrower, 1000e6, 1000e6, 1000e6);
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.deal(borrower, 100 ether);
        deal(usdc, borrower, 10000e6);

    }
}
