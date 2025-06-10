// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {Constants} from "contracts/v1/lib/Constants.sol";
import {ITermMaxMarket, TermMaxMarket, MarketEvents} from "contracts/v1/TermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {IGearingToken, AbstractGearingToken} from "contracts/v1/tokens/AbstractGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/v1/oracle/OracleAggregator.sol";
import {
    TermMaxRouter, ISwapAdapter, ITermMaxRouter, SwapUnit, RouterErrors
} from "contracts/v1/router/TermMaxRouter.sol";
import {UniswapV3Adapter, ERC20SwapAdapter} from "contracts/v1/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/v1/router/swapAdapters/PendleSwapV3Adapter.sol";
import {OdosV2Adapter, IOdosRouterV2} from "contracts/v1/router/swapAdapters/OdosV2Adapter.sol";
import {TermMaxOrder, ITermMaxOrder} from "contracts/v1/TermMaxOrder.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {RouterEvents} from "contracts/v1/events/RouterEvents.sol";
import {MockFlashLoanReceiver} from "contracts/v1/test/MockFlashLoanReceiver.sol";
import {TermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {VaultErrors, VaultEvents, ITermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {OrderManager} from "contracts/v1/vault/OrderManager.sol";
import {VaultConstants} from "contracts/v1/lib/VaultConstants.sol";
import {PendingAddress, PendingUint192} from "contracts/v1/lib/PendingLib.sol";
import "contracts/v1/storage/TermMaxStorage.sol";

abstract contract VaultBaseTest is ForkBaseTest {
    struct VaultTestRes {
        uint256 blockNumber;
        uint256 orderInitialAmount;
        MarketInitialParams marketInitialParams;
        OrderConfig orderConfig;
        TermMaxMarket market;
        IMintableERC20 ft;
        IMintableERC20 xt;
        IGearingToken gt;
        IERC20Metadata collateral;
        IERC20Metadata debtToken;
        IOracle oracle;
        MockPriceFeed collateralPriceFeed;
        MockPriceFeed debtPriceFeed;
        ITermMaxOrder order;
        ITermMaxVault vault;
        VaultInitialParams vaultInitialParams;
        uint256 currentTime;
        uint256 maxCapacity;
        address maker;
    }

    function _initializeVaultTestRes(string memory key) internal returns (VaultTestRes memory) {
        VaultTestRes memory res;
        res.blockNumber = _readBlockNumber(key);
        res.orderInitialAmount = vm.parseJsonUint(jsonData, string.concat(key, ".orderInitialAmount"));
        res.marketInitialParams = _readMarketInitialParams(key);
        res.orderConfig = _readOrderConfig(key);
        res.maker = vm.randomAddress();

        vm.rollFork(res.blockNumber);
        res.currentTime = block.timestamp;

        _generateVaultInitialParams(res);

        vm.startPrank(res.marketInitialParams.admin);

        res.oracle = deployOracleAggregator(res.marketInitialParams.admin);
        res.collateralPriceFeed = deployMockPriceFeed(res.marketInitialParams.admin);
        res.debtPriceFeed = deployMockPriceFeed(res.marketInitialParams.admin);
        res.oracle.submitPendingOracle(
            address(res.marketInitialParams.collateral),
            IOracle.Oracle(res.collateralPriceFeed, res.collateralPriceFeed, 365 days)
        );
        res.oracle.submitPendingOracle(
            address(res.marketInitialParams.debtToken), IOracle.Oracle(res.debtPriceFeed, res.debtPriceFeed, 365 days)
        );
        res.oracle.acceptPendingOracle(address(res.marketInitialParams.collateral));
        res.oracle.acceptPendingOracle(address(res.marketInitialParams.debtToken));

        res.marketInitialParams.marketConfig.maturity += uint64(block.timestamp);
        res.marketInitialParams.loanConfig.oracle = res.oracle;

        res.market = TermMaxMarket(
            deployFactoryWithMockOrder(res.marketInitialParams.admin).createMarket(
                keccak256("GearingTokenWithERC20"), res.marketInitialParams, 0
            )
        );

        (res.ft, res.xt, res.gt,,) = res.market.tokens();
        res.debtToken = res.marketInitialParams.debtToken;
        res.collateral = IERC20Metadata(res.marketInitialParams.collateral);

        // set all price as 1 USD = 1e8 tokens
        uint8 debtDecimals = res.debtToken.decimals();
        _setPriceFeedInTokenDecimal8(
            res.debtPriceFeed, debtDecimals, MockPriceFeed.RoundData(1, 1e8, block.timestamp, block.timestamp, 0)
        );
        uint8 collateralDecimals = res.collateral.decimals();
        _setPriceFeedInTokenDecimal8(
            res.collateralPriceFeed,
            collateralDecimals,
            MockPriceFeed.RoundData(1, 1e8, block.timestamp, block.timestamp, 0)
        );

        res.vault = ITermMaxVault(deployVaultFactory().createVault(res.vaultInitialParams, 0));

        res.vault.submitMarket(address(res.market), true);
        vm.warp(res.currentTime + res.vaultInitialParams.timelock + 1);
        res.vault.acceptMarket(address(res.market));

        vm.warp(res.currentTime);

        res.orderInitialAmount = vm.parseJsonUint(jsonData, string.concat(key, ".orderInitialAmount"));
        deal(address(res.debtToken), res.marketInitialParams.admin, res.orderInitialAmount);

        res.debtToken.approve(address(res.vault), res.orderInitialAmount);
        res.vault.deposit(res.orderInitialAmount, res.marketInitialParams.admin);

        res.order = res.vault.createOrder(
            res.market, res.vaultInitialParams.maxCapacity, res.orderInitialAmount, res.orderConfig.curveCuts
        );

        vm.stopPrank();

        return res;
    }

    function _generateVaultInitialParams(VaultTestRes memory res) internal {
        res.vaultInitialParams.admin = res.marketInitialParams.admin;
        res.vaultInitialParams.curator = vm.randomAddress();
        res.vaultInitialParams.timelock = 1 days;
        res.vaultInitialParams.asset = res.marketInitialParams.debtToken;
        res.vaultInitialParams.maxCapacity = type(uint128).max;
        res.vaultInitialParams.name = string.concat("Vault-", res.marketInitialParams.tokenName);
        res.vaultInitialParams.symbol = res.vaultInitialParams.name;
        res.vaultInitialParams.performanceFeeRate = 0.1e8;
    }

    function _testDeposit(VaultTestRes memory res) internal {
        _buyXt(res, 48.219178e8, uint128(res.orderInitialAmount / 100));
        vm.warp(res.currentTime + 2 days);
        address lper2 = vm.randomAddress();
        uint256 amount2 = 20000e8;
        deal(lper2, 1e18);
        deal(address(res.debtToken), lper2, amount2);
        vm.startPrank(lper2);
        res.debtToken.approve(address(res.vault), amount2);
        uint256 share = res.vault.previewDeposit(amount2);
        res.vault.deposit(amount2, lper2);
        assertEq(res.vault.balanceOf(lper2), share);

        vm.stopPrank();
    }

    function _testRedeem(VaultTestRes memory res) internal {
        vm.warp(res.currentTime + 2 days);
        _buyXt(res, 48.219178e8, uint128(res.orderInitialAmount / 100));
        vm.warp(res.currentTime + 4 days);
        address lper2 = vm.randomAddress();
        uint256 amount2 = 10000e8;
        deal(lper2, 1e18);
        deal(address(res.debtToken), lper2, amount2);
        vm.startPrank(lper2);
        res.debtToken.approve(address(res.vault), amount2);
        res.vault.deposit(amount2, lper2);
        vm.stopPrank();

        address admin = res.marketInitialParams.admin;
        vm.startPrank(admin);
        uint256 share = res.vault.balanceOf(admin);
        uint256 redeem = res.vault.previewRedeem(share);
        assertEq(redeem, res.vault.redeem(share, admin, admin));
        assertGt(redeem, amount2);
        vm.stopPrank();
    }

    function _testBadDebt(VaultTestRes memory res) internal {
        vm.warp(res.currentTime + 2 days);
        _buyXt(res, 48.219178e8, uint128(res.orderInitialAmount / 100));

        vm.warp(res.currentTime + 3 days);
        address lper2 = vm.randomAddress();
        deal(lper2, 1e18);
        uint256 amount2 = 100e8;
        deal(address(res.debtToken), lper2, amount2);
        vm.startPrank(lper2);
        res.debtToken.approve(address(res.vault), amount2);
        res.vault.deposit(amount2, lper2);
        vm.stopPrank();

        address borrower = vm.randomAddress();
        vm.startPrank(borrower);
        deal(borrower, 1e18);
        uint256 collateralAmt = 1e18;
        deal(address(res.collateral), borrower, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        res.market.issueFt(borrower, uint128(res.orderInitialAmount / 10), abi.encode(collateralAmt));
        vm.stopPrank();

        vm.warp(res.currentTime + 92 days);

        uint256 propotion = (res.ft.balanceOf(address(res.order)) * Constants.DECIMAL_BASE_SQ)
            / (res.ft.totalSupply() - res.ft.balanceOf(address(res.market)));

        uint256 tokenOut = (res.debtToken.balanceOf(address(res.market)) * propotion) / Constants.DECIMAL_BASE_SQ;
        uint256 badDebt = res.ft.balanceOf(address(res.order)) - tokenOut;
        uint256 delivered = (propotion * 1e18) / Constants.DECIMAL_BASE_SQ;

        vm.startPrank(lper2);
        res.vault.redeem(10e8, lper2, lper2);
        vm.stopPrank();

        assertEq(res.vault.badDebtMapping(address(res.collateral)), badDebt);
        assertEq(res.collateral.balanceOf(address(res.vault)), delivered);

        uint256 shareToDealBadDebt = res.vault.balanceOf(lper2);
        uint256 withdrawAmt = res.vault.previewRedeem(shareToDealBadDebt);
        if (withdrawAmt > badDebt) {
            withdrawAmt = badDebt;
        }

        vm.startPrank(lper2);
        (uint256 shares, uint256 collateralOut) =
            res.vault.dealBadDebt(address(res.collateral), withdrawAmt, lper2, lper2);
        assertEq(shares, shareToDealBadDebt);
        assertEq(collateralOut, (withdrawAmt * delivered) / badDebt);
        assertEq(res.vault.badDebtMapping(address(res.collateral)), badDebt - withdrawAmt);
        assertEq(res.collateral.balanceOf(address(res.vault)), delivered - collateralOut);
        vm.stopPrank();
    }

    function _buyXt(VaultTestRes memory res, uint128 tokenAmtIn, uint128 xtAmtOut) internal {
        address taker = vm.randomAddress();
        deal(taker, 1e18);
        deal(address(res.debtToken), taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debtToken.approve(address(res.order), tokenAmtIn);
        res.order.swapExactTokenToToken(res.debtToken, res.xt, taker, tokenAmtIn, xtAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }
}
