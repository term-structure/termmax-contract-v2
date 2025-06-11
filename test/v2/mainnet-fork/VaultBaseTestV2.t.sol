// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";
import {ForkBaseTestV2} from "./ForkBaseTestV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TermMaxFactoryV2, ITermMaxFactory} from "contracts/v2/factory/TermMaxFactoryV2.sol";
import {ITermMaxRouterV2, TermMaxRouterV2} from "contracts/v2/router/TermMaxRouterV2.sol";
import {TermMaxMarketV2, Constants, SafeCast, MarketEvents} from "contracts/v2/TermMaxMarketV2.sol";
import {TermMaxOrderV2, OrderConfig} from "contracts/v2/TermMaxOrderV2.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockOrderV2} from "contracts/v2/test/MockOrderV2.sol";
import {MintableERC20V2} from "contracts/v2/tokens/MintableERC20V2.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {SwapAdapter} from "contracts/v1/test/testnet/SwapAdapter.sol";
import {IOracleV2, OracleAggregatorV2} from "contracts/v2/oracle/OracleAggregatorV2.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {IOrderManager, OrderManager} from "contracts/v1/vault/OrderManager.sol";
import {ITermMaxVault, ITermMaxVaultV2, TermMaxVaultV2} from "contracts/v2/vault/TermMaxVaultV2.sol";
import {VaultFactory, IVaultFactory} from "contracts/v1/factory/VaultFactory.sol";
import {
    MarketConfig,
    FeeConfig,
    MarketInitialParams,
    LoanConfig,
    VaultInitialParams,
    CurveCuts
} from "contracts/v1/storage/TermMaxStorage.sol";
import {ITermMaxRouter, RouterEvents, RouterErrors} from "contracts/v1/router/TermMaxRouter.sol";
import {MockFlashLoanReceiver} from "contracts/v1/test/MockFlashLoanReceiver.sol";
import {SwapUnit, ISwapAdapter} from "contracts/v1/router/ISwapAdapter.sol";
import {
    IGearingToken, IGearingTokenV2, GearingTokenWithERC20V2
} from "contracts/v2/tokens/GearingTokenWithERC20V2.sol";
import {MintableERC20V2} from "contracts/v2/tokens/MintableERC20V2.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {ISwapCallback} from "contracts/v1/ISwapCallback.sol";
import {UniswapV3AdapterV2} from "contracts/v2/router/swapAdapters/UniswapV3AdapterV2.sol";
import {PendleSwapV3AdapterV2} from "contracts/v2/router/swapAdapters/PendleSwapV3AdapterV2.sol";
import {OdosV2AdapterV2} from "contracts/v2/router/swapAdapters/OdosV2AdapterV2.sol";
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {KyberswapV2AdapterV2} from "contracts/v2/router/swapAdapters/KyberswapV2AdapterV2.sol";
import {OrderManager} from "contracts/v1/vault/OrderManager.sol";
import {VaultConstants} from "contracts/v1/lib/VaultConstants.sol";
import {PendingAddress, PendingUint192} from "contracts/v1/lib/PendingLib.sol";
import {ITermMaxVault} from "contracts/v1/vault/ITermMaxVault.sol";
import {ITermMaxVaultV2, VaultErrors, VaultEvents, TermMaxVaultV2} from "contracts/v2/vault/TermMaxVaultV2.sol";
import {VaultInitialParamsV2} from "contracts/v2/storage/TermMaxStorageV2.sol";
import {TermMaxVaultFactoryV2} from "contracts/v2/factory/TermMaxVaultFactoryV2.sol";

abstract contract VaultBaseTestV2 is ForkBaseTestV2 {
    using SafeCast for *;

    struct VaultTestRes {
        uint256 blockNumber;
        uint256 orderInitialAmount;
        MarketInitialParams marketInitialParams;
        OrderConfig orderConfig;
        TermMaxMarketV2 market;
        IMintableERC20 ft;
        IMintableERC20 xt;
        IGearingToken gt;
        IERC20Metadata collateral;
        IERC20Metadata debtToken;
        IOracleV2 oracle;
        MockPriceFeed collateralPriceFeed;
        MockPriceFeed debtPriceFeed;
        ITermMaxOrder order;
        ITermMaxVault vault;
        VaultInitialParamsV2 vaultInitialParams;
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
            IOracleV2.Oracle(res.collateralPriceFeed, res.collateralPriceFeed, 365 days, 365 days, 0)
        );
        res.oracle.submitPendingOracle(
            address(res.marketInitialParams.debtToken),
            IOracleV2.Oracle(res.debtPriceFeed, res.debtPriceFeed, 365 days, 365 days, 0)
        );
        res.oracle.acceptPendingOracle(address(res.marketInitialParams.collateral));
        res.oracle.acceptPendingOracle(address(res.marketInitialParams.debtToken));

        res.marketInitialParams.marketConfig.maturity += uint64(block.timestamp);
        res.marketInitialParams.loanConfig.oracle = IOracle(address(res.oracle));

        res.market = TermMaxMarketV2(
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

        _depositToOrder(res.vault, res.order, amount2.toInt256());

        address borrower = vm.randomAddress();
        vm.startPrank(borrower);
        deal(borrower, 1e18);
        uint256 collateralAmt = 100000e18;
        deal(address(res.collateral), borrower, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        res.market.issueFt(borrower, uint128(res.orderInitialAmount / 10), abi.encode(collateralAmt));
        vm.stopPrank();

        vm.warp(res.currentTime + 92 days);

        uint256 propotion = (res.ft.balanceOf(address(res.order)) * Constants.DECIMAL_BASE_SQ)
            / (res.ft.totalSupply() - res.ft.balanceOf(address(res.market)));

        uint256 tokenOut = (res.debtToken.balanceOf(address(res.market)) * propotion) / Constants.DECIMAL_BASE_SQ;
        uint256 badDebt = res.ft.balanceOf(address(res.order)) - tokenOut;
        uint256 delivered = (propotion * collateralAmt) / Constants.DECIMAL_BASE_SQ;

        vm.startPrank(lper2);
        res.vault.redeemOrder(res.order);
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

    function _depositToOrder(ITermMaxVault vault, ITermMaxOrder order, int256 amount) internal {
        vm.startPrank(vault.curator());
        CurveCuts[] memory curveCuts = new CurveCuts[](1);
        curveCuts[0] = order.orderConfig().curveCuts;
        int256[] memory amounts = new int256[](1);
        amounts[0] = amount;
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = order;
        uint256[] memory maxSupplies = new uint256[](1);
        maxSupplies[0] = type(uint128).max;
        vault.updateOrders(orders, amounts, maxSupplies, curveCuts);
        vm.stopPrank();
    }
}
