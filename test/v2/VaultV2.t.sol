// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFlashLoanReceiver} from "contracts/v1/IFlashLoanReceiver.sol";
import {
    ITermMaxMarketV2,
    ITermMaxMarket,
    TermMaxMarketV2,
    Constants,
    MarketErrors,
    MarketEvents
} from "contracts/v2/TermMaxMarketV2.sol";
import {ITermMaxOrder, TermMaxOrderV2, ISwapCallback, OrderEvents} from "contracts/v2/TermMaxOrderV2.sol";
import {MockERC20, ERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockFlashLoanReceiver} from "contracts/v1/test/MockFlashLoanReceiver.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {
    VaultInitialParams,
    MarketConfig,
    MarketInitialParams,
    LoanConfig,
    OrderConfig,
    CurveCuts,
    IOracle
} from "contracts/v1/storage/TermMaxStorage.sol";
import {
    ITermMaxVaultV2,
    TermMaxVaultV2,
    VaultErrors,
    VaultEvents,
    VaultErrorsV2,
    VaultEventsV2,
    VaultConstants,
    OrderV2ConfigurationParams
} from "contracts/v2/vault/TermMaxVaultV2.sol";
import {ITermMaxVault, OrderInfo} from "contracts/v1/vault/ITermMaxVault.sol";
import {PendingUint192, PendingLib} from "contracts/v1/lib/PendingLib.sol";
import {VaultErrorsV2} from "contracts/v2/errors/VaultErrorsV2.sol";
import {IPausable} from "contracts/v1/access/AccessManager.sol";
import {VaultEventsV2} from "contracts/v2/events/VaultEventsV2.sol";
import {VaultInitialParamsV2} from "contracts/v2/storage/TermMaxStorageV2.sol";

/// @dev use --isolate to run this tests
contract VaultTestV2 is Test {
    using JSONLoader for *;
    using SafeCast for *;

    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address curator = vm.randomAddress();
    address guardian = vm.randomAddress();
    address lper = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    TermMaxVaultV2 vault;

    uint256 timelock = 86400;
    uint256 maxCapacity = 1000000e18;
    uint64 performanceFeeRate = 0.5e8;

    ITermMaxMarket market2;

    uint256 currentTime;
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;
    VaultInitialParamsV2 initialParams;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        currentTime = vm.parseUint(vm.parseJsonString(testdata, ".currentTime"));
        vm.warp(currentTime);

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");
        marketConfig.maturity = uint64(currentTime + 90 days);
        res = DeployUtils.deployMockMarket(deployer, marketConfig, maxLtv, liquidationLtv);
        vm.label(address(res.market), "market");
        MarketConfig memory marketConfig2 = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        marketConfig2.maturity = uint64(currentTime + 180 days);

        market2 = ITermMaxMarket(
            res.factory.createMarket(
                DeployUtils.GT_ERC20,
                MarketInitialParams({
                    collateral: address(res.collateral),
                    debtToken: res.debt,
                    admin: deployer,
                    gtImplementation: address(0),
                    marketConfig: marketConfig2,
                    loanConfig: LoanConfig({
                        maxLtv: maxLtv,
                        liquidationLtv: liquidationLtv,
                        liquidatable: true,
                        oracle: IOracle(address(res.oracle))
                    }),
                    gtInitalParams: abi.encode(type(uint256).max),
                    tokenName: "test",
                    tokenSymbol: "test"
                }),
                0
            )
        );
        vm.label(address(market2), "market2");

        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        uint256 amount = 10000e8;

        initialParams = VaultInitialParamsV2(
            deployer,
            curator,
            guardian,
            timelock,
            res.debt,
            maxCapacity,
            "Vault-DAI",
            "Vault-DAI",
            performanceFeeRate,
            0,
            0
        );

        vault = DeployUtils.deployVault(initialParams);

        vm.label(address(vault), "vault");
        vm.label(guardian, "guardian");
        vm.label(curator, "curator");
        vm.label(deployer, "deployer");
        vm.label(lper, "lper");
        vm.label(address(res.debt), "debt token");
        vm.label(address(res.collateral), "collateral token");

        vault.submitMarket(address(res.market), true);
        vault.submitMarket(address(market2), true);
        vm.warp(currentTime + timelock + 1);
        vault.acceptMarket(address(res.market));
        vault.acceptMarket(address(market2));
        vm.warp(currentTime);

        res.debt.mint(deployer, amount);
        res.debt.approve(address(vault), amount);
        vault.deposit(amount, deployer);
        assertEq(res.debt.balanceOf(address(vault)), amount);

        OrderV2ConfigurationParams memory orderConfigParams = OrderV2ConfigurationParams({
            maxXtReserve: maxCapacity,
            virtualXtReserve: amount,
            liquidityChanges: amount.toInt256()
        });

        res.order = TermMaxOrderV2(
            address(vault.createOrder(res.market, IERC4626(address(0)), orderConfigParams, orderConfig.curveCuts))
        );
        vm.label(address(res.order), "order");
        res.debt.mint(deployer, 10000e18);
        res.debt.approve(address(res.market), 10000e18);
        res.market.mint(deployer, 10000e18);
        vm.stopPrank();
    }

    function testRoleManagement() public {
        // Test initial roles
        assertEq(vault.guardian(), guardian);
        assertEq(vault.curator(), curator);

        // Test guardian role checks
        vm.startPrank(deployer);
        address newGuardian = address(0x123);
        vault.submitGuardian(newGuardian);

        // Should not be set immediately due to timelock
        assertEq(vault.guardian(), guardian);

        // Move forward past timelock
        vm.warp(block.timestamp + timelock + 1);
        vault.acceptGuardian();
        assertEq(vault.guardian(), newGuardian);
        vm.stopPrank();

        // Test revoke guardian
        address nextGuardian = address(0x456);
        vm.prank(deployer);
        vault.submitGuardian(nextGuardian);

        vm.prank(newGuardian);
        vault.revokePendingGuardian();
        assertEq(vault.pendingGuardian().value, address(0));

        // Test curator role
        vm.prank(deployer);
        address newCurator = address(0x456);
        vault.setCurator(newCurator);
        assertEq(vault.curator(), newCurator);
    }

    function test_RevertSetGuardian() public {
        address newGuardian = address(0x123);
        address alice = vm.randomAddress();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.submitGuardian(newGuardian);

        vm.startPrank(deployer);
        vault.submitGuardian(newGuardian);

        vm.expectRevert(VaultErrors.AlreadyPending.selector);
        vault.submitGuardian(newGuardian);

        vm.expectRevert(VaultErrors.TimelockNotElapsed.selector);
        vault.acceptGuardian();

        vm.warp(block.timestamp + 1 days + 1);
        vault.acceptGuardian();

        vm.expectRevert(VaultErrors.AlreadySet.selector);
        vault.submitGuardian(address(0x123));

        vm.stopPrank();
    }

    function testMarketWhitelist() public {
        // check current timelock value
        assertEq(vault.timelock(), 86400);

        // submit market
        vm.startPrank(curator);
        address market = address(0x123);
        vault.submitMarket(market, false);

        assertEq(vault.marketWhitelist(market), false);
        vault.submitMarket(market, true);

        assertEq(vault.marketWhitelist(market), false);

        // The validAt of the newly submitted market is the current time, without timelock
        PendingUint192 memory pendingMarket = vault.pendingMarkets(market);
        assertEq(pendingMarket.validAt, block.timestamp + 86400);

        vm.warp(block.timestamp + 86400 + 1);
        vault.acceptMarket(market);
        assertEq(vault.marketWhitelist(market), true);

        vault.submitMarket(market, false);
        assertEq(vault.marketWhitelist(market), false);
        vm.stopPrank();

        // Test revoke market
        address newMarket = address(0x456);
        vm.prank(curator);
        vault.submitMarket(newMarket, true);

        vm.prank(guardian);
        vault.revokePendingMarket(newMarket);
        assertEq(vault.pendingMarkets(newMarket).validAt, 0);
    }

    function test_RevertSetMarketWhitelist() public {
        address market = address(0x123);

        vm.prank(vm.randomAddress());
        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vault.submitMarket(market, true);

        vm.startPrank(curator);
        vault.submitMarket(market, true);

        vm.expectRevert(VaultErrors.AlreadyPending.selector);
        vault.submitMarket(market, true);

        vm.expectRevert(VaultErrors.TimelockNotElapsed.selector);
        vault.acceptMarket(market);

        vm.warp(block.timestamp + 86400 + 1);
        vault.acceptMarket(market);

        vm.expectRevert(VaultErrors.AlreadySet.selector);
        vault.submitMarket(market, true);

        vm.stopPrank();
    }

    function test_RevertCreateOrder() public {
        ITermMaxMarketV2 market = ITermMaxMarketV2(address(0x123));
        address bob = lper;
        vm.startPrank(bob);

        OrderV2ConfigurationParams memory orderConfigParams =
            OrderV2ConfigurationParams({maxXtReserve: maxCapacity, virtualXtReserve: 0, liquidityChanges: 0});

        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vault.createOrder(market, IERC4626(address(0)), orderConfigParams, orderConfig.curveCuts);

        vm.stopPrank();

        vm.startPrank(curator);
        vm.expectRevert(abi.encodeWithSelector(VaultErrorsV2.MarketNotWhitelisted.selector, address(market)));
        vault.createOrder(market, IERC4626(address(0)), orderConfigParams, orderConfig.curveCuts);
        vm.stopPrank();
    }

    function testTimelockManagement() public {
        uint256 newTimelock = 2 days;

        vm.prank(curator);
        vault.submitTimelock(newTimelock);
        assertEq(vault.timelock(), newTimelock);

        newTimelock = 1.5 days;
        vm.prank(curator);
        vault.submitTimelock(newTimelock);
        assertEq(vault.timelock(), 2 days);

        PendingUint192 memory pendingTimelock = vault.pendingTimelock();
        assertEq(uint256(pendingTimelock.value), newTimelock);
        assertEq(vault.timelock(), 2 days);

        // Can accept after timelock period
        vm.warp(currentTime + 2 days);
        vm.prank(vm.randomAddress());
        vault.acceptTimelock();
        assertEq(vault.timelock(), newTimelock);

        // revoke
        vm.warp(currentTime + 3 days);
        vm.prank(curator);
        vault.submitTimelock(1 days);
        vm.prank(guardian);
        vault.revokePendingTimelock();
        pendingTimelock = vault.pendingTimelock();
        assertEq(uint256(pendingTimelock.value), 0);
    }

    function test_RevertSetTimelock() public {
        uint256 newTimelock = 2 days;
        vm.startPrank(curator);

        vault.submitTimelock(newTimelock);

        vm.expectRevert(VaultErrors.AlreadySet.selector);
        vault.submitTimelock(newTimelock);

        newTimelock = 1.5 days;
        vault.submitTimelock(newTimelock);

        vm.expectRevert(VaultErrors.AlreadyPending.selector);
        vault.submitTimelock(newTimelock);

        vm.warp(currentTime + 2 days);
        vault.acceptTimelock();

        vm.expectRevert(VaultErrors.BelowMinTimelock.selector);
        vault.submitTimelock(1 days - 1);

        vm.expectRevert(VaultErrors.AboveMaxTimelock.selector);
        vault.submitTimelock(VaultConstants.MAX_TIMELOCK + 1);

        vm.expectRevert(VaultErrors.NoPendingValue.selector);
        vault.acceptTimelock();

        vault.submitTimelock(1 days);
        vm.warp(currentTime + 0.9 days);
        vm.expectRevert(VaultErrors.TimelockNotElapsed.selector);
        vault.acceptTimelock();

        vm.stopPrank();

        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vault.submitTimelock(1 days);
    }

    function testPerformanceFeeRate() public {
        uint184 newPercentage = 0.4e8;

        vm.prank(curator);
        vault.submitPerformanceFeeRate(newPercentage);

        uint256 percentage = vault.performanceFeeRate();
        assertEq(percentage, newPercentage);

        newPercentage = 0.5e8;
        vm.prank(curator);
        vault.submitPerformanceFeeRate(newPercentage);

        vm.prank(guardian);
        vault.revokePendingPerformanceFeeRate();

        vm.prank(curator);
        vault.submitPerformanceFeeRate(newPercentage);

        PendingUint192 memory pendingFeeRate = vault.pendingPerformanceFeeRate();
        assertEq(uint256(pendingFeeRate.value), newPercentage);

        vm.warp(pendingFeeRate.validAt);
        vm.prank(vm.randomAddress());
        vault.acceptPerformanceFeeRate();
        percentage = vault.performanceFeeRate();
        assertEq(percentage, newPercentage);
    }

    function test_RevertSetPerformanceFeeRate() public {
        uint184 newPercentage = 0.5e8;

        vm.prank(curator);
        vm.expectRevert(VaultErrors.AlreadySet.selector);
        vault.submitPerformanceFeeRate(newPercentage);

        newPercentage = 0.6e8;
        vm.prank(curator);
        vm.expectRevert(VaultErrors.PerformanceFeeRateExceeded.selector);
        vault.submitPerformanceFeeRate(newPercentage);

        vm.prank(vm.randomAddress());
        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vault.submitPerformanceFeeRate(newPercentage);

        newPercentage = 0.4e8;
        vm.startPrank(curator);
        vault.submitPerformanceFeeRate(newPercentage);

        newPercentage = 0.41e8;
        vault.submitPerformanceFeeRate(newPercentage);

        newPercentage = 0.42e8;
        vm.expectRevert(VaultErrors.AlreadyPending.selector);
        vault.submitPerformanceFeeRate(newPercentage);

        vm.stopPrank();
    }

    function testDeposit() public {
        vm.warp(currentTime + 2 days);
        buyXt(48.219178e8, 1000e8);

        vm.warp(currentTime + 2 days);
        address lper2 = vm.randomAddress();
        uint256 amount2 = 20000e8;
        res.debt.mint(lper2, amount2);
        vm.startPrank(lper2);
        res.debt.approve(address(vault), amount2);
        uint256 share = vault.previewDeposit(amount2);
        vault.deposit(amount2, lper2);
        assertEq(vault.balanceOf(lper2), share);

        vm.stopPrank();
    }

    function testDepositWhenNoOrders() public {
        initialParams.name = "Vault-DAI2";
        initialParams.symbol = "Vault-DAI2";
        TermMaxVaultV2 vault2 = DeployUtils.deployVault(initialParams);
        vm.startPrank(deployer);
        uint256 amount = 10000e8;
        res.debt.mint(deployer, amount);
        res.debt.approve(address(vault2), amount);
        uint256 share = vault2.previewDeposit(amount);
        vault2.deposit(amount, deployer);
        assertEq(vault2.balanceOf(deployer), share);
        assertEq(vault2.totalFt(), amount);
        assertEq(vault2.totalAssets(), amount);
        assertEq(vault2.totalSupply(), share);
        vm.stopPrank();

        vm.startPrank(lper);
        res.debt.mint(lper, amount);
        res.debt.approve(address(vault2), amount);
        uint256 share2 = vault2.previewDeposit(amount);
        vault2.deposit(amount, lper);
        assertEq(vault2.balanceOf(lper), share2);
        assertEq(vault2.totalFt(), amount + amount);
        assertEq(vault2.totalAssets(), amount + amount);
        assertEq(vault2.totalSupply(), share + share2);
        vm.stopPrank();
    }

    function testRedeem() public {
        vm.warp(currentTime + 2 days);
        buyXt(48.219178e8, 1000e8);
        vm.warp(currentTime + 4 days);
        address lper2 = vm.randomAddress();
        uint256 amount2 = 10000e8;
        res.debt.mint(lper2, amount2);
        vm.startPrank(lper2);
        res.debt.approve(address(vault), amount2);
        vault.deposit(amount2, lper2);
        vm.stopPrank();

        _depositToOrder(vault, res.order, -1e10);

        vm.startPrank(deployer);
        uint256 totalFt = vault.totalFt();
        uint256 lockedFr = vault.totalAssets();

        uint256 share = vault.balanceOf(deployer);
        uint256 redeemmedAmt = vault.previewRedeem(share);
        assertEq(redeemmedAmt, vault.redeem(share, deployer, deployer));
        assert(redeemmedAmt > 10000e8);
        assertEq(vault.totalFt(), totalFt - redeemmedAmt);
        assertEq(vault.totalAssets(), lockedFr - redeemmedAmt);

        vm.stopPrank();
    }

    // redeem when balance bigger tha redeemed
    function testRedeemCase2() public {
        vm.warp(currentTime + 2 days);
        buyXt(48.219178e8, 1000e8);

        vm.warp(currentTime + 4 days);
        address lper2 = vm.randomAddress();
        uint256 amount2 = 10000e8;
        res.debt.mint(lper2, amount2);
        vm.startPrank(lper2);
        res.debt.approve(address(vault), amount2);
        vault.deposit(amount2, lper2);
        vm.stopPrank();

        vm.startPrank(curator);
        address[] memory orders = new address[](1);
        orders[0] = address(res.order);

        OrderV2ConfigurationParams[] memory orderConfigParamsArray = new OrderV2ConfigurationParams[](1);
        orderConfigParamsArray[0] =
            OrderV2ConfigurationParams({maxXtReserve: maxCapacity, virtualXtReserve: 0, liquidityChanges: -1000e8});

        vault.updateOrdersConfigAndLiquidity(orders, orderConfigParamsArray);
        vm.stopPrank();

        vm.startPrank(deployer);
        uint256 totalFt = vault.totalFt();
        uint256 lockedFr = vault.totalAssets();

        uint256 share = 100e8;
        uint256 redeemmedAmt = vault.previewRedeem(share);
        assertEq(redeemmedAmt, vault.redeem(share, deployer, deployer));
        assert(redeemmedAmt > share);
        assertEq(vault.totalFt(), totalFt - redeemmedAmt);
        assertEq(vault.totalAssets(), lockedFr - redeemmedAmt);

        vm.stopPrank();
    }

    function testActions() public {
        console.log("----day 2----");
        vm.warp(currentTime + 2 days);
        buyXt(48.219178e8, 1000e8);
        console.log("anulizedInterest:", vault.annualizedInterest());
        console.log("apy:", ITermMaxVaultV2(address(vault)).apy());

        console.log("----day 3----");
        vm.warp(currentTime + 3 days);
        console.log("new principal:", vault.totalAssets());
        address lper2 = vm.randomAddress();
        uint256 amount2 = 10000e8;
        res.debt.mint(lper2, amount2);
        vm.startPrank(lper2);
        res.debt.approve(address(vault), amount2);
        vault.deposit(amount2, lper2);
        vm.stopPrank();
        _depositToOrder(vault, res.order, amount2.toInt256());
        console.log("principal after deposit:", vault.totalAssets());
        console.log("total supply:", vault.totalSupply());
        console.log("anulizedInterest:", vault.annualizedInterest());
        console.log("apy:", ITermMaxVaultV2(address(vault)).apy());

        console.log("----day 4----");
        vm.warp(currentTime + 4 days);
        swapFtToXt(94.247e8, 2000e8);
        console.log("1-principal after swap:", vault.totalAssets());
        console.log("1-anulizedInterest:", vault.annualizedInterest());
        console.log("1-apy:", ITermMaxVaultV2(address(vault)).apy());
        swapFtToXt(94.247e8, 2000e8);
        console.log("2-principal after swap:", vault.totalAssets());
        console.log("2-anulizedInterest:", vault.annualizedInterest());
        console.log("2-apy:", ITermMaxVaultV2(address(vault)).apy());

        console.log("----day 6----");
        vm.warp(currentTime + 6 days);
        console.log("new principal:", vault.totalAssets());
        _depositToOrder(vault, res.order, -(vault.previewRedeem(1000e8)).toInt256());
        vm.startPrank(lper2);
        console.log("previewRedeem: ", vault.previewRedeem(1000e8));
        assertEq(vault.previewRedeem(1000e8), vault.redeem(1000e8, lper2, lper2));
        console.log("principal after redeem:", vault.totalAssets());
        console.log("total supply:", vault.totalSupply());
        console.log("anulizedInterest:", vault.annualizedInterest());
        console.log("apy:", ITermMaxVaultV2(address(vault)).apy());
        vm.stopPrank();

        console.log("----day 91----");
        vm.warp(currentTime + 91 days);
        console.log("new principal:", vault.totalAssets());
        console.log("previewRedeem: ", vault.previewRedeem(1000e8));

        console.log("----day 92----");
        vm.warp(currentTime + 92 days);
        console.log("new principal:", vault.totalAssets());
        vm.startPrank(lper2);
        console.log("previewRedeem: ", vault.previewRedeem(1000e8));
        vault.redeemOrder(res.order);
        assertEq(vault.previewRedeem(1000e8), vault.redeem(1000e8, lper2, lper2));
        console.log("principal after redeem:", vault.totalAssets());
        console.log("total supply:", vault.totalSupply());
        console.log("anulizedInterest:", vault.annualizedInterest());
        console.log("apy:", ITermMaxVaultV2(address(vault)).apy());
        vm.stopPrank();
    }

    function testAnulizedInterestLessThanZero() public {
        uint128 tokenAmtIn = 100e8;
        uint128 ftAmtOut = 100e8;
        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);
        vm.expectRevert(VaultErrors.OrderHasNegativeInterest.selector);
        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, ftAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function testLockedFtGreaterThanTotalFt() public {
        vm.warp(currentTime + 2 days);
        buyXt(50e8, 1000e8);

        vm.warp(currentTime + 4 days);
        uint128 tokenAmtIn = 80e8;
        uint128 ftAmtOut = 130e8;

        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);

        vm.expectRevert(VaultErrors.LockedFtGreaterThanTotalFt.selector);
        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, ftAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function testOrderHasNegativeInterest() public {
        vm.warp(currentTime + 2 days);
        uint128 tokenAmtIn = 90e8;
        uint128 ftAmtOut = 100e8;
        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);
        vm.expectRevert(VaultErrors.OrderHasNegativeInterest.selector);
        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, ftAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function testBadDebt() public {
        vm.warp(currentTime + 2 days);
        buyXt(48.219178e8, 1000e8);

        vm.warp(currentTime + 3 days);
        address lper2 = vm.randomAddress();
        vm.label(lper2, "lper2");
        uint256 amount2 = 10000e8;
        res.debt.mint(lper2, amount2);
        vm.startPrank(lper2);
        res.debt.approve(address(vault), amount2);
        vault.deposit(amount2, lper2);
        assertEq(res.debt.balanceOf(address(vault)), amount2);
        vm.stopPrank();

        _depositToOrder(vault, res.order, amount2.toInt256());

        address borrower = vm.randomAddress();
        vm.startPrank(borrower);
        LoanUtils.fastMintGt(res, borrower, 1000e8, 1e18);
        vm.stopPrank();

        vm.warp(marketConfig.maturity + 1 days);

        uint256 propotion = (res.ft.balanceOf(address(res.order)) * Constants.DECIMAL_BASE_SQ)
            / (res.ft.totalSupply() - res.ft.balanceOf(address(res.market)));

        uint256 tokenOut = (res.debt.balanceOf(address(res.market)) * propotion) / Constants.DECIMAL_BASE_SQ;
        uint256 badDebt = res.ft.balanceOf(address(res.order)) - tokenOut;
        uint256 delivered = (propotion * 1e18) / Constants.DECIMAL_BASE_SQ;

        vm.startPrank(lper2);
        vault.redeemOrder(res.order);
        vault.redeem(1000e8, lper2, lper2);
        vm.stopPrank();

        assertEq(vault.badDebtMapping(address(res.collateral)), badDebt);
        assertEq(res.collateral.balanceOf(address(vault)), delivered);

        uint256 shareToDealBadDebt = vault.previewWithdraw(badDebt / 2);
        vm.startPrank(lper2);
        (uint256 shares, uint256 collateralOut) = vault.dealBadDebt(address(res.collateral), badDebt / 2, lper2, lper2);
        assertEq(shares, shareToDealBadDebt);
        assertEq(collateralOut, ((badDebt / 2) * delivered) / badDebt);
        assertEq(vault.badDebtMapping(address(res.collateral)), badDebt - badDebt / 2);
        assertEq(res.collateral.balanceOf(address(vault)), delivered - collateralOut);
        vm.stopPrank();

        vm.startPrank(lper2);
        shareToDealBadDebt = vault.previewWithdraw(badDebt - badDebt / 2);
        uint256 remainningCollateral = res.collateral.balanceOf(address(vault));
        vm.expectEmit();
        emit VaultEvents.DealBadDebt(
            lper2, lper2, address(res.collateral), badDebt - badDebt / 2, shareToDealBadDebt, remainningCollateral
        );
        (shares, collateralOut) = vault.dealBadDebt(address(res.collateral), badDebt - badDebt / 2, lper2, lper2);
        assertEq(shares, shareToDealBadDebt);
        assertEq(collateralOut, remainningCollateral);
        assertEq(vault.badDebtMapping(address(res.collateral)), 0);
        assertEq(res.collateral.balanceOf(address(vault)), 0);
        vm.stopPrank();
    }

    function testDealBadDebtRevert() public {
        vm.warp(currentTime + 2 days);
        buyXt(48.219178e8, 1000e8);

        vm.warp(currentTime + 3 days);
        address lper2 = vm.randomAddress();
        uint256 amount2 = 10000e8;
        res.debt.mint(lper2, amount2);
        vm.startPrank(lper2);
        res.debt.approve(address(vault), amount2);
        vault.deposit(amount2, lper2);
        vm.stopPrank();

        _depositToOrder(vault, res.order, amount2.toInt256());

        address borrower = vm.randomAddress();
        vm.startPrank(borrower);
        LoanUtils.fastMintGt(res, borrower, 1000e8, 1e18);
        vm.stopPrank();

        vm.warp(currentTime + 92 days);
        vm.startPrank(lper2);
        vault.redeemOrder(res.order);
        vault.redeem(1000e8, lper2, lper2);

        uint256 badDebt = vault.badDebtMapping(address(res.collateral));
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.InsufficientFunds.selector, badDebt, 2000e8));
        vault.dealBadDebt(address(res.collateral), 2000e8, lper2, lper2);

        vault.dealBadDebt(address(res.collateral), badDebt, lper2, lper2);

        vm.expectRevert(abi.encodeWithSelector(VaultErrors.NoBadDebt.selector, address(res.collateral)));
        vault.dealBadDebt(address(res.collateral), 10e8, lper2, lper2);

        vm.expectRevert(abi.encodeWithSelector(VaultErrorsV2.CollateralIsAsset.selector));
        vault.dealBadDebt(address(res.debt), 10e8, lper2, lper2); // Update to use asset() for the test

        vm.stopPrank();
    }

    function testSwapWhenVaultIsPaused() public {
        vm.prank(deployer);
        IPausable(address(vault)).pause();
        address taker = vm.randomAddress();
        uint128 tokenAmtIn = 1e8;
        uint128 ftAmtOut = 1.2e8;
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, ftAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function buyFt(uint128 tokenAmtIn, uint128 ftAmtOut) internal {
        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);
        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, ftAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function buyXt(uint128 tokenAmtIn, uint128 xtAmtOut) internal {
        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);
        res.order.swapExactTokenToToken(res.debt, res.xt, taker, tokenAmtIn, xtAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function sellFt(uint128 ftAmtIn, uint128 tokenAmtOut) internal {
        address taker = vm.randomAddress();
        vm.prank(deployer);
        res.ft.transfer(taker, ftAmtIn);
        vm.startPrank(taker);
        res.ft.approve(address(res.order), ftAmtIn);
        res.order.swapExactTokenToToken(res.ft, res.debt, taker, ftAmtIn, tokenAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function sellXt(uint128 xtAmtIn, uint128 tokenAmtOut) internal {
        address taker = vm.randomAddress();
        vm.prank(deployer);
        res.xt.transfer(taker, xtAmtIn);
        vm.startPrank(taker);
        res.xt.approve(address(res.order), xtAmtIn);
        res.order.swapExactTokenToToken(res.xt, res.debt, taker, xtAmtIn, tokenAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function swapFtToXt(uint128 ftAmtIn, uint128 xtAmtOut) internal {
        address taker = vm.randomAddress();
        vm.prank(deployer);
        res.ft.transfer(taker, ftAmtIn);
        vm.startPrank(taker);
        res.ft.approve(address(res.order), ftAmtIn);
        res.order.swapExactTokenToToken(res.ft, res.xt, taker, ftAmtIn, xtAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function swapXtToFt(uint128 xtAmtIn, uint128 ftAmtOut) internal {
        address taker = vm.randomAddress();
        vm.prank(deployer);
        res.xt.transfer(taker, xtAmtIn);
        vm.startPrank(taker);
        res.xt.approve(address(res.order), xtAmtIn);
        res.order.swapExactTokenToToken(res.xt, res.ft, taker, xtAmtIn, ftAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function testFixFindings101() public {
        vm.prank(curator);
        OrderV2ConfigurationParams memory orderConfigParams =
            OrderV2ConfigurationParams({maxXtReserve: maxCapacity, virtualXtReserve: 0, liquidityChanges: 0});

        vault.createOrder(res.market, IERC4626(address(0)), orderConfigParams, orderConfig.curveCuts);
        lper = vm.randomAddress();

        res.debt.mint(lper, 100 ether);

        // depositing funds for lp1
        vm.startPrank(lper);
        res.debt.approve(address(vault), 100 ether);
        vault.deposit(100 ether, lper);
        vm.stopPrank();

        vm.warp(currentTime + 110 days);

        vm.startPrank(lper);
        vault.withdraw(100 ether, lper, lper);
    }

    function _daysToMaturity(uint256 _now) internal view returns (uint256 daysToMaturity) {
        daysToMaturity = (res.market.config().maturity - _now + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }

    function _depositToOrder(TermMaxVaultV2 _vault, TermMaxOrderV2 order, int256 amount) internal {
        vm.startPrank(_vault.curator());

        OrderV2ConfigurationParams[] memory orderConfigParamsArray = new OrderV2ConfigurationParams[](1);
        orderConfigParamsArray[0] =
            OrderV2ConfigurationParams({maxXtReserve: maxCapacity, virtualXtReserve: 0, liquidityChanges: amount});
        address[] memory orders = new address[](1);
        orders[0] = address(order);

        _vault.updateOrdersConfigAndLiquidity(orders, orderConfigParamsArray);
        vm.stopPrank();
    }

    // ========== Tests for ITermMaxVaultV2 new functions ==========

    function testMinApyManagement() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Test initial state
        assertEq(vaultV2.minApy(), 0);
        assertEq(vaultV2.pendingMinApy().value, 0);
        assertEq(vaultV2.pendingMinApy().validAt, 0);

        // Test submitPendingMinApy - increase (immediate)
        uint64 newMinApy = 0.05e8; // 5%
        vm.prank(curator);
        vaultV2.submitPendingMinApy(newMinApy);

        // Should be set immediately for increases
        assertEq(vaultV2.minApy(), newMinApy);
        assertEq(vaultV2.pendingMinApy().value, 0);

        // Test submitPendingMinApy - decrease (timelock required)
        uint64 lowerMinApy = 0.03e8; // 3%
        vm.prank(curator);
        vaultV2.submitPendingMinApy(lowerMinApy);

        // Should not be set immediately for decreases
        assertEq(vaultV2.minApy(), newMinApy);
        assertEq(vaultV2.pendingMinApy().value, lowerMinApy);
        assertEq(vaultV2.pendingMinApy().validAt, block.timestamp + timelock);

        // Test acceptPendingMinApy before timelock
        vm.expectRevert(VaultErrors.TimelockNotElapsed.selector);
        vaultV2.acceptPendingMinApy();

        // Test acceptPendingMinApy after timelock
        vm.warp(block.timestamp + timelock + 1);
        vaultV2.acceptPendingMinApy();

        assertEq(vaultV2.minApy(), lowerMinApy);
        assertEq(vaultV2.pendingMinApy().value, 0);
        assertEq(vaultV2.pendingMinApy().validAt, 0);
    }

    function testMinApyRevoke() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Set initial minApy
        uint64 initialMinApy = 0.05e8;
        vm.prank(curator);
        vaultV2.submitPendingMinApy(initialMinApy);

        // Submit decrease
        uint64 lowerMinApy = 0.03e8;
        vm.prank(curator);
        vaultV2.submitPendingMinApy(lowerMinApy);

        // Guardian revokes pending change
        vm.prank(guardian);
        vaultV2.revokePendingMinApy();

        assertEq(vaultV2.minApy(), initialMinApy);
        assertEq(vaultV2.pendingMinApy().value, 0);
        assertEq(vaultV2.pendingMinApy().validAt, 0);
    }

    function testMinIdleFundRateManagement() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Test initial state
        assertEq(vaultV2.minIdleFundRate(), 0);
        assertEq(vaultV2.pendingMinIdleFundRate().value, 0);
        assertEq(vaultV2.pendingMinIdleFundRate().validAt, 0);

        // Test submitPendingMinIdleFundRate - increase (immediate)
        uint64 newMinIdleFundRate = 0.1e8; // 10%
        vm.prank(curator);
        vaultV2.submitPendingMinIdleFundRate(newMinIdleFundRate);

        // Should be set immediately for increases
        assertEq(vaultV2.minIdleFundRate(), newMinIdleFundRate);
        assertEq(vaultV2.pendingMinIdleFundRate().value, 0);

        // Test submitPendingMinIdleFundRate - decrease (timelock required)
        uint64 lowerMinIdleFundRate = 0.05e8; // 5%
        vm.prank(curator);
        vaultV2.submitPendingMinIdleFundRate(lowerMinIdleFundRate);

        // Should not be set immediately for decreases
        assertEq(vaultV2.minIdleFundRate(), newMinIdleFundRate);
        assertEq(vaultV2.pendingMinIdleFundRate().value, lowerMinIdleFundRate);
        assertEq(vaultV2.pendingMinIdleFundRate().validAt, block.timestamp + timelock);

        // Test acceptPendingMinIdleFundRate before timelock
        vm.expectRevert(VaultErrors.TimelockNotElapsed.selector);
        vaultV2.acceptPendingMinIdleFundRate();

        // Test acceptPendingMinIdleFundRate after timelock
        vm.warp(block.timestamp + timelock + 1);
        vaultV2.acceptPendingMinIdleFundRate();

        assertEq(vaultV2.minIdleFundRate(), lowerMinIdleFundRate);
        assertEq(vaultV2.pendingMinIdleFundRate().value, 0);
        assertEq(vaultV2.pendingMinIdleFundRate().validAt, 0);
    }

    function testMinIdleFundRateRevoke() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Set initial minIdleFundRate
        uint64 initialMinIdleFundRate = 0.1e8;
        vm.prank(curator);
        vaultV2.submitPendingMinIdleFundRate(initialMinIdleFundRate);

        // Submit decrease
        uint64 lowerMinIdleFundRate = 0.05e8;
        vm.prank(curator);
        vaultV2.submitPendingMinIdleFundRate(lowerMinIdleFundRate);

        // Guardian revokes pending change
        vm.prank(guardian);
        vaultV2.revokePendingMinIdleFundRate();

        assertEq(vaultV2.minIdleFundRate(), initialMinIdleFundRate);
        assertEq(vaultV2.pendingMinIdleFundRate().value, 0);
        assertEq(vaultV2.pendingMinIdleFundRate().validAt, 0);
    }

    function testApyFunction() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Initially should return 0 when no accreting principal
        assertEq(vaultV2.apy(), 0);

        // After some trading activity, APY should be calculated correctly
        vm.warp(currentTime + 2 days);
        buyXt(48.219178e8, 1000e8);

        uint256 apy = vaultV2.apy();
        uint256 annualizedInterest = vault.annualizedInterest();
        uint256 accretingPrincipal = vault.accretingPrincipal();
        uint256 performanceFeeRate = vault.performanceFeeRate();

        // APY should be calculated as: (annualizedInterest * (1 - performanceFeeRate)) / accretingPrincipal
        uint256 expectedApy = (annualizedInterest * (Constants.DECIMAL_BASE - performanceFeeRate)) / accretingPrincipal;
        assertEq(apy, expectedApy);

        // APY should be greater than 0 after trading
        assertGt(apy, 0);
    }

    function test_RevertMinApyAccessControl() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Test unauthorized access
        vm.prank(vm.randomAddress());
        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vaultV2.submitPendingMinApy(0.05e8);

        vm.prank(vm.randomAddress());
        vm.expectRevert(VaultErrors.NotGuardianRole.selector);
        vaultV2.revokePendingMinApy();
    }

    function test_RevertMinIdleFundRateAccessControl() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Test unauthorized access
        vm.prank(vm.randomAddress());
        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vaultV2.submitPendingMinIdleFundRate(0.1e8);

        vm.prank(vm.randomAddress());
        vm.expectRevert(VaultErrors.NotGuardianRole.selector);
        vaultV2.revokePendingMinIdleFundRate();
    }

    function test_RevertMinApyAlreadySet() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        uint64 minApy = 0.05e8;
        vm.startPrank(curator);
        vaultV2.submitPendingMinApy(minApy);

        // Should revert when trying to set the same value
        vm.expectRevert(VaultErrors.AlreadySet.selector);
        vaultV2.submitPendingMinApy(minApy);

        vm.stopPrank();
    }

    function test_RevertMinIdleFundRateAlreadySet() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        uint64 minIdleFundRate = 0.1e8;
        vm.startPrank(curator);
        vaultV2.submitPendingMinIdleFundRate(minIdleFundRate);

        // Should revert when trying to set the same value
        vm.expectRevert(VaultErrors.AlreadySet.selector);
        vaultV2.submitPendingMinIdleFundRate(minIdleFundRate);

        vm.stopPrank();
    }

    function test_RevertMinApyAlreadyPending() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        vm.startPrank(curator);
        // Set initial value
        vaultV2.submitPendingMinApy(0.05e8);

        // Submit decrease (creates pending)
        vaultV2.submitPendingMinApy(0.03e8);

        // Should revert when trying to submit another pending change
        vm.expectRevert(VaultErrors.AlreadyPending.selector);
        vaultV2.submitPendingMinApy(0.02e8);

        vm.stopPrank();
    }

    function test_RevertMinIdleFundRateAlreadyPending() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        vm.startPrank(curator);
        // Set initial value
        vaultV2.submitPendingMinIdleFundRate(0.1e8);

        // Submit decrease (creates pending)
        vaultV2.submitPendingMinIdleFundRate(0.05e8);

        // Should revert when trying to submit another pending change
        vm.expectRevert(VaultErrors.AlreadyPending.selector);
        vaultV2.submitPendingMinIdleFundRate(0.03e8);

        vm.stopPrank();
    }

    function test_RevertAcceptMinApyNoPendingValue() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Should revert when no pending value exists
        vm.expectRevert(VaultErrors.NoPendingValue.selector);
        vaultV2.acceptPendingMinApy();
    }

    function test_RevertAcceptMinIdleFundRateNoPendingValue() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Should revert when no pending value exists
        vm.expectRevert(VaultErrors.NoPendingValue.selector);
        vaultV2.acceptPendingMinIdleFundRate();
    }

    function testMinApyEventEmission() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Test SetMinApy event for immediate increase
        uint64 newMinApy = 0.05e8;
        vm.expectEmit(true, false, false, true);
        emit VaultEventsV2.SetMinApy(curator, newMinApy);

        vm.prank(curator);
        vaultV2.submitPendingMinApy(newMinApy);

        // Test SubmitMinApy event for timelock decrease
        uint64 lowerMinApy = 0.03e8;
        vm.expectEmit(false, false, false, true);
        emit VaultEventsV2.SubmitMinApy(lowerMinApy, uint64(block.timestamp + timelock));

        vm.prank(curator);
        vaultV2.submitPendingMinApy(lowerMinApy);

        // Test SetMinApy event when accepting pending value
        vm.warp(block.timestamp + timelock + 1);
        vm.expectEmit(true, false, false, true);
        emit VaultEventsV2.SetMinApy(address(this), lowerMinApy);

        vaultV2.acceptPendingMinApy();
    }

    function testMinIdleFundRateEventEmission() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Test SetMinIdleFundRate event for immediate increase
        uint64 newMinIdleFundRate = 0.1e8;
        vm.expectEmit(true, false, false, true);
        emit VaultEventsV2.SetMinIdleFundRate(curator, newMinIdleFundRate);

        vm.prank(curator);
        vaultV2.submitPendingMinIdleFundRate(newMinIdleFundRate);

        // Test SubmitMinIdleFundRate event for timelock decrease
        uint64 lowerMinIdleFundRate = 0.05e8;
        vm.expectEmit(false, false, false, true);
        emit VaultEventsV2.SubmitMinIdleFundRate(lowerMinIdleFundRate, uint64(block.timestamp + timelock));

        vm.prank(curator);
        vaultV2.submitPendingMinIdleFundRate(lowerMinIdleFundRate);

        // Test SetMinIdleFundRate event when accepting pending value
        vm.warp(block.timestamp + timelock + 1);
        vm.expectEmit(true, false, false, true);
        emit VaultEventsV2.SetMinIdleFundRate(address(this), lowerMinIdleFundRate);

        vaultV2.acceptPendingMinIdleFundRate();
    }

    function testRevokeEventEmission() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Set up pending changes
        vm.startPrank(curator);
        vaultV2.submitPendingMinApy(0.05e8);
        vaultV2.submitPendingMinApy(0.03e8); // Creates pending
        vaultV2.submitPendingMinIdleFundRate(0.1e8);
        vaultV2.submitPendingMinIdleFundRate(0.05e8); // Creates pending
        vm.stopPrank();

        // Test RevokePendingMinApy event
        vm.expectEmit(true, false, false, false);
        emit VaultEventsV2.RevokePendingMinApy(guardian);

        vm.prank(guardian);
        vaultV2.revokePendingMinApy();

        // Test RevokePendingMinIdleFundRate event
        vm.expectEmit(true, false, false, false);
        emit VaultEventsV2.RevokePendingMinIdleFundRate(guardian);

        vm.prank(guardian);
        vaultV2.revokePendingMinIdleFundRate();
    }

    function testRevertWhenIdleFundTooLow() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));
        vm.startPrank(curator);
        vaultV2.submitPendingMinIdleFundRate(0.1e8); // minIdleFundRate = 10%

        // Withdraw 3000e8 from the order
        OrderV2ConfigurationParams[] memory orderConfigParams = new OrderV2ConfigurationParams[](1);
        orderConfigParams[0] =
            OrderV2ConfigurationParams({maxXtReserve: maxCapacity, virtualXtReserve: 0, liquidityChanges: -3000e8});

        address[] memory orders = new address[](1);
        orders[0] = address(res.order);
        vault.updateOrdersConfigAndLiquidity(orders, orderConfigParams);

        orderConfigParams[0].liquidityChanges = 3000e8; // deposit 3000e8 from the order
        vm.expectRevert(abi.encodeWithSelector(VaultErrorsV2.IdleFundRateTooLow.selector, 0, 0.1e8));
        vault.updateOrdersConfigAndLiquidity(orders, orderConfigParams);

        vm.stopPrank();
    }

    function testRevertWhenApyTooLow() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));
        vm.prank(curator);
        vaultV2.submitPendingMinApy(0.05e8); // minApy = 5%

        sellFt(1000e8, 800e8); // Sell 100e8 FT

        uint128 tokenAmtIn = 800e8;
        uint128 ftAmtOut = 1000e8;
        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);

        vm.expectRevert(abi.encodeWithSelector(VaultErrorsV2.ApyTooLow.selector, 0, 0.05e8));
        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, ftAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    // ========== Tests for ITermMaxVaultV2 nonTxReentrantBetweenActions ==========
    /// @dev remove --isolate to run this test
    function testMultipleDeposits() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        // Initial deposit
        vm.startPrank(deployer);
        res.debt.mint(deployer, 1000e8);
        res.debt.approve(address(vault), 1000e8);
        vault.deposit(1000e8, deployer);
        vm.stopPrank();

        // Second deposit
        vm.startPrank(deployer);
        res.debt.mint(deployer, 500e8);
        res.debt.approve(address(vault), 500e8);
        vault.deposit(500e8, deployer);
        vm.stopPrank();
    }

    /// @dev remove --isolate to run this test
    function testMultipleWithdrawals() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(vault));

        _depositToOrder(vault, res.order, -10e8.toInt256());

        // First withdrawal
        vm.startPrank(deployer);
        uint256 sharesToWithdraw = 1e2;
        uint256 amountWithdrawn = vault.withdraw(sharesToWithdraw, deployer, deployer);
        assertEq(amountWithdrawn, vault.previewWithdraw(sharesToWithdraw));
        vm.stopPrank();

        // Second withdrawal
        vm.startPrank(deployer);
        sharesToWithdraw = 1e3;
        amountWithdrawn = vault.withdraw(sharesToWithdraw, deployer, deployer);
        assertEq(amountWithdrawn, vault.previewWithdraw(sharesToWithdraw));
        vm.stopPrank();
    }
}
