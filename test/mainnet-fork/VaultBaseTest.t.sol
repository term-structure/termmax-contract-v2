// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {ITermMaxMarket, TermMaxMarket, MarketEvents} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {IGearingToken, AbstractGearingToken} from "contracts/tokens/AbstractGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";
import {TermMaxRouter, ISwapAdapter, ITermMaxRouter, SwapUnit, RouterErrors} from "contracts/router/TermMaxRouter.sol";
import {UniswapV3Adapter, ERC20SwapAdapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {OdosV2Adapter, IOdosRouterV2} from "contracts/router/swapAdapters/OdosV2Adapter.sol";
import {EnvConfig} from "test/mainnet-fork/EnvConfig.sol";
import {TermMaxOrder, ITermMaxOrder} from "contracts/TermMaxOrder.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {RouterEvents} from "contracts/events/RouterEvents.sol";
import {MockFlashLoanReceiver} from "contracts/test/MockFlashLoanReceiver.sol";
import {TermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {VaultErrors, VaultEvents, ITermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {OrderManager} from "contracts/vault/OrderManager.sol";
import {VaultConstants} from "contracts/lib/VaultConstants.sol";
import {PendingAddress, PendingUint192} from "contracts/lib/PendingLib.sol";
import "contracts/storage/TermMaxStorage.sol";

abstract contract VaultBaseTest is ForkBaseTest {

    MarketInitialParams marketInitialParams;

    TermMaxMarket market;
    IMintableERC20 ft;
    IMintableERC20 xt;
    IGearingToken gt;
    IERC20 collateral;
    IERC20 debtToken;
    IOracle oracle;
    MockPriceFeed collateralPriceFeed;
    MockPriceFeed debtPriceFeed;
    ITermMaxOrder order;
    ITermMaxVault vault;
    VaultInitialParams vaultInitialParams;

    uint currentTime;

    function _initialize(bytes memory data) internal override {
        currentTime = block.timestamp;
        CurveCuts memory curveCuts;
        (marketInitialParams, curveCuts, vaultInitialParams) = abi.decode(data, (MarketInitialParams, CurveCuts, VaultInitialParams));

        deal(vaultInitialParams.curator, 1e18);
        deal(marketInitialParams.admin, 1e18);
        vm.startPrank(marketInitialParams.admin);

        oracle = deployOracleAggregator(marketInitialParams.admin);
        collateralPriceFeed = deployMockPriceFeed(marketInitialParams.admin);
        debtPriceFeed = deployMockPriceFeed(marketInitialParams.admin);
        oracle.setOracle(
            address(marketInitialParams.collateral), IOracle.Oracle(collateralPriceFeed, collateralPriceFeed, 365 days)
        );
        oracle.setOracle(address(marketInitialParams.debtToken), IOracle.Oracle(debtPriceFeed, debtPriceFeed, 365 days));

        marketInitialParams.marketConfig.maturity += uint64(currentTime);
        marketInitialParams.loanConfig.oracle = oracle;

        market = TermMaxMarket(
            deployFactoryWithMockOrder(marketInitialParams.admin).createMarket(
                keccak256("GearingTokenWithERC20"), marketInitialParams, 0
            )
        );

        (ft, xt, gt,,) = market.tokens();
        debtToken = marketInitialParams.debtToken;
        collateral = IERC20(marketInitialParams.collateral);

        vault = ITermMaxVault(deployVaultFactory().createVault(vaultInitialParams, 0));

        vault.submitMarket(address(market), true);
        vm.warp(currentTime + vaultInitialParams.timelock + 1);
        vault.acceptMarket(address(market));

        vm.warp(currentTime);

        uint256 amount = 10000e18;
        deal(address(debtToken), marketInitialParams.admin, amount);

        debtToken.approve(address(vault), amount);
        vault.deposit(amount, marketInitialParams.admin);

        order = vault.createOrder(market, vaultInitialParams.maxCapacity, amount, curveCuts);

        vm.stopPrank();
    }

    function testDeposit() public {
        _buyXt(48.219178e8, 1000e8);
        vm.warp(currentTime + 2 days);
        address lper2 = vm.randomAddress();
        uint256 amount2 = 20000e8;
        deal(lper2, 1e18);
        deal(address(debtToken), lper2, amount2);
        vm.startPrank(lper2);
        debtToken.approve(address(vault), amount2);
        uint256 share = vault.previewDeposit(amount2);
        vault.deposit(amount2, lper2);
        assertEq(vault.balanceOf(lper2), share);

        vm.stopPrank();
    }

    function testRedeem() public {
        vm.warp(currentTime + 2 days);
        _buyXt(48.219178e8, 1000e8);
        vm.warp(currentTime + 4 days);
        address lper2 = vm.randomAddress();
        uint256 amount2 = 10000e8;
        deal(lper2, 1e18);
        deal(address(debtToken), lper2, amount2);
        vm.startPrank(lper2);
        debtToken.approve(address(vault), amount2);
        vault.deposit(amount2, lper2);
        vm.stopPrank();

        address admin = marketInitialParams.admin;
        vm.startPrank(admin);
        uint256 share = vault.balanceOf(admin);
        uint256 redeem = vault.previewRedeem(share);
        assertEq(redeem, vault.redeem(share, admin, admin));
        assertGt(redeem, 10000e8);
        vm.stopPrank();
    }

    function testBadDebt() public {
        vm.warp(currentTime + 2 days);
        _buyXt(48.219178e8, 1000e8);

        vm.warp(currentTime + 3 days);
        address lper2 = vm.randomAddress();
        deal(lper2, 1e18);
        uint256 amount2 = 10000e8;
        deal(address(debtToken), lper2, amount2);
        vm.startPrank(lper2);
        debtToken.approve(address(vault), amount2);
        vault.deposit(amount2, lper2);
        vm.stopPrank();

        address borrower = vm.randomAddress();
        vm.startPrank(borrower);
        deal(borrower, 1e18);
        uint collateralAmt = 1e18;
        deal(address(collateral), borrower, collateralAmt);
        collateral.approve(address(gt), collateralAmt);
        market.issueFt(borrower, 0.01e18, abi.encode(collateralAmt));
        vm.stopPrank();

        vm.warp(currentTime + 92 days);

        uint256 propotion = (ft.balanceOf(address(order)) * Constants.DECIMAL_BASE_SQ)
            / (ft.totalSupply() - ft.balanceOf(address(market)));

        uint256 tokenOut = (debtToken.balanceOf(address(market)) * propotion) / Constants.DECIMAL_BASE_SQ;
        uint256 badDebt = ft.balanceOf(address(order)) - tokenOut;
        uint256 delivered = (propotion * 1e18) / Constants.DECIMAL_BASE_SQ;

        vm.startPrank(lper2);
        vault.redeem(1000e8, lper2, lper2);
        vm.stopPrank();

        assertEq(vault.badDebtMapping(address(collateral)), badDebt);
        assertEq(collateral.balanceOf(address(vault)), delivered);

        uint256 shareToDealBadDebt = vault.previewWithdraw(badDebt / 2);
        vm.startPrank(lper2);
        (uint256 shares, uint256 collateralOut) = vault.dealBadDebt(address(collateral), badDebt / 2, lper2, lper2);
        assertEq(shares, shareToDealBadDebt);
        assertEq(collateralOut, ((badDebt / 2) * delivered) / badDebt);
        assertEq(vault.badDebtMapping(address(collateral)), badDebt - badDebt / 2);
        assertEq(collateral.balanceOf(address(vault)), delivered - collateralOut);
        vm.stopPrank();

        vm.startPrank(lper2);
        shareToDealBadDebt = vault.previewWithdraw(badDebt - badDebt / 2);
        uint256 remainningCollateral = collateral.balanceOf(address(vault));
        vm.expectEmit();
        emit VaultEvents.DealBadDebt(
            lper2, lper2, address(collateral), badDebt - badDebt / 2, shareToDealBadDebt, remainningCollateral
        );
        (shares, collateralOut) = vault.dealBadDebt(address(collateral), badDebt - badDebt / 2, lper2, lper2);
        assertEq(shares, shareToDealBadDebt);
        assertEq(collateralOut, remainningCollateral);
        assertEq(vault.badDebtMapping(address(collateral)), 0);
        assertEq(collateral.balanceOf(address(vault)), 0);
        vm.stopPrank();
    }

    function _buyXt(uint128 tokenAmtIn, uint128 xtAmtOut) internal {
        address taker = vm.randomAddress();
        deal(taker, 1e18);
        deal(address(debtToken), taker, tokenAmtIn);
        vm.startPrank(taker);
        debtToken.approve(address(order), tokenAmtIn);
        order.swapExactTokenToToken(debtToken, xt, taker, tokenAmtIn, xtAmtOut);
        vm.stopPrank();
    }

}
