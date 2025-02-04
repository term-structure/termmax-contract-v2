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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFlashLoanReceiver} from "contracts/IFlashLoanReceiver.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, MarketEvents, MarketErrors} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder, TermMaxOrder, ISwapCallback, OrderEvents, OrderErrors} from "contracts/TermMaxOrder.sol";
import {MockERC20, ERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {TermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {VaultErrors, VaultEvents, ITermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {OrderManager} from "contracts/vault/OrderManager.sol";
import {VaultConstants} from "contracts/lib/VaultConstants.sol";
import {PendingAddress, PendingUint192} from "contracts/lib/PendingLib.sol";
import "contracts/storage/TermMaxStorage.sol";

contract VaultTest is Test {
    using JSONLoader for *;
    using SafeCast for *;
    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address curator = vm.randomAddress();
    address allocator = vm.randomAddress();
    address guardian = vm.randomAddress();
    address lper = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    ITermMaxVault vault;

    uint timelock = 86400;
    uint maxCapacity = 1000000e18;
    uint64 performanceFeeRate = 0.5e8;

    ITermMaxMarket market2;

    uint currentTime;
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;
    VaultInitialParams initialParams;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        currentTime = vm.parseUint(vm.parseJsonString(testdata, ".currentTime"));
        vm.warp(currentTime);

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");
        marketConfig.maturity = uint64(currentTime + 90 days);
        res = DeployUtils.deployMockMarket(deployer, marketConfig, maxLtv, liquidationLtv);
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
                        oracle: res.oracle
                    }),
                    gtInitalParams: abi.encode(type(uint256).max),
                    tokenName: "test",
                    tokenSymbol: "test"
                }),
                0
            )
        );

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth")
        );
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        uint amount = 10000e8;

        initialParams = VaultInitialParams(
            deployer,
            curator,
            timelock,
            res.debt,
            maxCapacity,
            "Vault-DAI",
            "Vault-DAI",
            performanceFeeRate
        );

        vault = DeployUtils.deployVault(initialParams);

        vault.submitGuardian(guardian);
        vault.setIsAllocator(allocator, true);

        vault.submitMarket(address(res.market), true);
        vault.submitMarket(address(market2), true);
        vm.warp(currentTime + timelock + 1);
        vault.acceptMarket(address(res.market));
        vault.acceptMarket(address(market2));
        vm.warp(currentTime);

        res.debt.mint(deployer, amount);
        res.debt.approve(address(vault), amount);
        vault.deposit(amount, deployer);

        res.order = vault.createOrder(res.market, maxCapacity, amount, orderConfig.curveCuts);

        res.debt.mint(deployer, 10000e18);
        res.debt.approve(address(res.market), 10000e18);
        res.market.mint(deployer, 10000e18);
        vm.stopPrank();
    }

    function testRoleManagement() public {
        // Test initial roles
        assertEq(vault.guardian(), guardian);
        assertEq(vault.curator(), curator);
        assertTrue(vault.isAllocator(allocator));

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

        // Test curator role
        vm.prank(deployer);
        address newCurator = address(0x456);
        vault.setCurator(newCurator);
        assertEq(vault.curator(), newCurator);

        // Test allocator management
        vm.prank(deployer);
        address newAllocator = address(0x789);
        vault.setIsAllocator(newAllocator, true);
        assertTrue(vault.isAllocator(newAllocator));
    }

    function testFail_SetGuardian() public {
        address newGuardian = address(0x123);
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, allocator));
        vault.submitGuardian(newGuardian);

        vm.startPrank(deployer);
        vault.submitGuardian(newGuardian);
        vm.expectRevert(VaultErrors.AlreadySet.selector);
        vault.submitGuardian(newGuardian);

        vm.expectRevert(VaultErrors.AlreadyPending.selector);
        vault.submitGuardian(address(0x456));

        vm.expectRevert(VaultErrors.TimelockNotElapsed.selector);
        vault.acceptGuardian();

        vm.stopPrank();
    }

    function testMarketWhitelist() public {
        address market = address(0x123);

        vm.prank(curator);
        vault.submitMarket(market, true);

        // Should not be whitelisted before timelock
        assertFalse(vault.marketWhitelist(market));

        // After timelock passes
        vm.warp(block.timestamp + timelock + 1);
        vm.prank(vm.randomAddress());
        vault.acceptMarket(market);
        assertTrue(vault.marketWhitelist(market));

        vm.prank(curator);
        vault.submitMarket(market, false);
        assertFalse(vault.marketWhitelist(market));
    }

    function testFail_SetMarketWhitelist() public {
        address market = address(0x123);

        vm.prank(vm.randomAddress());
        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vault.submitMarket(market, true);

        vm.startPrank(curator);
        vault.submitMarket(market, true);

        vm.expectRevert(VaultErrors.AlreadySet.selector);
        vault.submitMarket(market, true);

        vm.expectRevert(VaultErrors.AlreadyPending.selector);
        vault.submitMarket(market, false);

        vm.stopPrank();
    }

    function testFail_CreateOrder() public {
        ITermMaxMarket market = ITermMaxMarket(address(0x123));
        address bob = lper;
        vm.startPrank(bob);

        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vault.createOrder(market, maxCapacity, 0, orderConfig.curveCuts);

        vm.stopPrank();

        vm.startPrank(curator);
        vm.expectRevert(VaultErrors.MarketNotWhitelisted.selector);
        vault.createOrder(market, maxCapacity, 0, orderConfig.curveCuts);
        marketConfig.maturity = uint64(currentTime + 360 days);
        ITermMaxMarket market3 = ITermMaxMarket(
            res.factory.createMarket(
                DeployUtils.GT_ERC20,
                MarketInitialParams({
                    collateral: address(res.collateral),
                    debtToken: res.debt,
                    admin: deployer,
                    gtImplementation: address(0),
                    marketConfig: marketConfig,
                    loanConfig: LoanConfig({
                        maxLtv: maxLtv,
                        liquidationLtv: liquidationLtv,
                        liquidatable: true,
                        oracle: res.oracle
                    }),
                    gtInitalParams: abi.encode(type(uint256).max),
                    tokenName: "test",
                    tokenSymbol: "test"
                }),
                0
            )
        );
        vault.submitMarket(address(market3), true);
        vm.warp(currentTime + timelock + 1);
        vault.acceptMarket(address(market3));
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
    }

    function testFail_SetTimelock() public {
        uint256 newTimelock = 2 days;
        vm.startPrank(curator);

        vault.submitTimelock(newTimelock);

        vm.expectRevert(VaultErrors.AlreadySet.selector);
        vault.submitTimelock(newTimelock);

        newTimelock = 1.5 days;

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

        uint percentage = vault.performanceFeeRate();
        assertEq(percentage, newPercentage);

        newPercentage = 0.5e8;
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

    function testFail_SetPerformanceFeeRate() public {
        uint184 newPercentage = 0.5e8;

        vm.prank(curator);
        vm.expectRevert(VaultErrors.PerformanceFeeRateExceeded.selector);
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

    function testSupplyQueue(uint orderCount, uint seed) public {
        vm.assume(orderCount < VaultConstants.MAX_QUEUE_LENGTH && orderCount > 0);
        address[] memory supplyQueue = new address[](orderCount);
        supplyQueue[0] = vault.supplyQueue(0);
        vm.startPrank(curator);
        for (uint i = 1; i < orderCount; i++) {
            address order = address(vault.createOrder(res.market, maxCapacity, 0, orderConfig.curveCuts));
            supplyQueue[i] = order;
            assertEq(vault.supplyQueue(i), order);
        }

        uint256[] memory indexes = new uint256[](orderCount);
        for (uint i = 0; i < orderCount; i++) {
            indexes[i] = i;
        }
        indexes = shuffle(indexes, seed);
        vault.updateSupplyQueue(indexes);

        for (uint i = 0; i < orderCount; i++) {
            assertEq(vault.supplyQueue(i), supplyQueue[indexes[i]]);
        }

        vm.stopPrank();
    }

    function testWithdrawQueue(uint orderCount, uint seed) public {
        vm.assume(orderCount < VaultConstants.MAX_QUEUE_LENGTH && orderCount > 0);
        address[] memory withdrawQueue = new address[](orderCount);
        withdrawQueue[0] = vault.withdrawQueue(0);
        vm.startPrank(curator);
        for (uint i = 1; i < orderCount; i++) {
            address order = address(vault.createOrder(res.market, maxCapacity, 0, orderConfig.curveCuts));
            withdrawQueue[i] = order;
            assertEq(vault.withdrawQueue(i), order);
        }

        uint256[] memory indexes = new uint256[](orderCount);
        for (uint i = 0; i < orderCount; i++) {
            indexes[i] = i;
        }
        indexes = shuffle(indexes, seed);
        vault.updateWithdrawQueue(indexes);

        for (uint i = 0; i < orderCount; i++) {
            assertEq(vault.withdrawQueue(i), withdrawQueue[indexes[i]]);
        }

        vm.stopPrank();
    }

    function shuffle(uint256[] memory arr, uint seed) public pure returns (uint256[] memory) {
        uint256 length = arr.length;

        for (uint256 i = length - 1; i > 0; i--) {
            uint256 j = seed % (i + 1);

            uint256 temp = arr[i];
            arr[i] = arr[j];
            arr[j] = temp;
        }

        return arr;
    }

    function testFail_SupplyQueue() public {
        vm.prank(lper);
        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vault.updateSupplyQueue(new uint256[](0));

        vm.startPrank(curator);
        vm.expectRevert(VaultErrors.SupplyQueueLengthMismatch.selector);
        vault.updateSupplyQueue(new uint256[](0));

        address order2 = address(vault.createOrder(res.market, maxCapacity, 0, orderConfig.curveCuts));
        uint[] memory indexes = new uint[](2);
        indexes[0] = 1;
        indexes[1] = 1;
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.DuplicateOrder.selector, order2));
        vault.updateSupplyQueue(indexes);

        vm.stopPrank();
    }

    function testFail_WithdrawQueue() public {
        vm.prank(lper);
        vm.expectRevert(VaultErrors.NotCuratorRole.selector);
        vault.updateWithdrawQueue(new uint256[](0));

        vm.startPrank(curator);
        vm.expectRevert(VaultErrors.WithdrawQueueLengthMismatch.selector);
        vault.updateWithdrawQueue(new uint256[](0));

        address order2 = address(vault.createOrder(res.market, maxCapacity, 0, orderConfig.curveCuts));
        uint[] memory indexes = new uint[](2);
        indexes[0] = 1;
        indexes[1] = 1;
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.DuplicateOrder.selector, order2));
        vault.updateWithdrawQueue(indexes);

        vm.stopPrank();
    }

    function testUpdateOrder() public {
        vm.startPrank(curator);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](3);
        orders[0] = res.order;
        orders[1] = vault.createOrder(res.market, maxCapacity, 0, orderConfig.curveCuts);
        orders[2] = vault.createOrder(res.market, maxCapacity, 0, orderConfig.curveCuts);

        int256[] memory changes = new int256[](3);
        changes[0] = -3000;
        changes[1] = 2000;
        changes[2] = 1000;

        uint256[] memory maxSupplies = new uint256[](3);
        maxSupplies[0] = maxCapacity - 1;
        maxSupplies[1] = maxCapacity + 1;
        maxSupplies[2] = maxCapacity;

        CurveCuts[] memory curveCuts = new CurveCuts[](3);
        CurveCuts memory newCurveCuts = orderConfig.curveCuts;
        newCurveCuts.lendCurveCuts[0].liqSquare++;
        curveCuts[0] = newCurveCuts;
        newCurveCuts.lendCurveCuts[0].liqSquare++;
        curveCuts[1] = newCurveCuts;
        newCurveCuts.lendCurveCuts[0].liqSquare++;
        curveCuts[2] = newCurveCuts;

        uint[] memory balancesBefore = new uint[](3);
        balancesBefore[0] = res.ft.balanceOf(address(orders[0]));
        balancesBefore[1] = res.ft.balanceOf(address(orders[1]));
        balancesBefore[2] = res.ft.balanceOf(address(orders[2]));
        vault.updateOrders(orders, changes, maxSupplies, curveCuts);

        for (uint i = 0; i < orders.length; i++) {
            assertEq(orders[i].orderConfig().maxXtReserve, maxSupplies[i]);
            if (changes[i] < 0) {
                assertEq(res.ft.balanceOf(address(orders[i])), balancesBefore[i] - (-changes[i]).toUint256());
            } else {
                assertEq(res.ft.balanceOf(address(orders[i])), balancesBefore[i] + changes[i].toUint256());
            }
            assertEq(
                orders[i].orderConfig().curveCuts.lendCurveCuts[0].liqSquare,
                curveCuts[i].lendCurveCuts[0].liqSquare
            );
        }

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
        uint share = vault.previewDeposit(amount2);
        vault.deposit(amount2, lper2);
        assertEq(vault.balanceOf(lper2), share);

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

        vm.startPrank(deployer);
        uint share = vault.balanceOf(deployer);
        uint redeem = vault.previewRedeem(share);
        assertEq(redeem, vault.redeem(share, deployer, deployer));
        assert(redeem > 10000e8);
        vm.stopPrank();
    }

    function testActions() public {
        console.log("----day 2----");
        vm.warp(currentTime + 2 days);
        buyXt(48.219178e8, 1000e8);
        console.log("anulizedInterest:", vault.annualizedInterest());
        console.log("apr:", vault.apr());

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
        console.log("principal after deposit:", vault.totalAssets());
        console.log("total supply:", vault.totalSupply());
        console.log("anulizedInterest:", vault.annualizedInterest());
        console.log("apr:", vault.apr());

        console.log("----day 4----");
        vm.warp(currentTime + 4 days);
        swapFtToXt(94.247e8, 2000e8);
        console.log("1-principal after swap:", vault.totalAssets());
        console.log("1-anulizedInterest:", vault.annualizedInterest());
        console.log("1-apr:", vault.apr());
        swapFtToXt(94.247e8, 2000e8);
        console.log("2-principal after swap:", vault.totalAssets());
        console.log("2-anulizedInterest:", vault.annualizedInterest());
        console.log("2-apr:", vault.apr());

        console.log("----day 6----");
        vm.warp(currentTime + 6 days);
        console.log("new principal:", vault.totalAssets());
        vm.startPrank(lper2);
        console.log("previewRedeem: ", vault.previewRedeem(1000e8));
        assertEq(vault.previewRedeem(1000e8), vault.redeem(1000e8, lper2, lper2));
        console.log("principal after redeem:", vault.totalAssets());
        console.log("total supply:", vault.totalSupply());
        console.log("anulizedInterest:", vault.annualizedInterest());
        console.log("apr:", vault.apr());
        vm.stopPrank();

        console.log("----day 91----");
        vm.warp(currentTime + 91 days);
        console.log("new principal:", vault.totalAssets());
        console.log("previewRedeem: ", vault.previewRedeem(1000e8));
        console.log("redeem fee ratio:", res.market.config().feeConfig.redeemFeeRatio);

        console.log("----day 92----");
        vm.warp(currentTime + 92 days);
        console.log("new principal:", vault.totalAssets());
        vm.startPrank(lper2);
        console.log("previewRedeem: ", vault.previewRedeem(1000e8));
        assertEq(vault.previewRedeem(1000e8), vault.redeem(1000e8, lper2, lper2));
        console.log("principal after redeem:", vault.totalAssets());
        console.log("total supply:", vault.totalSupply());
        console.log("anulizedInterest:", vault.annualizedInterest());
        console.log("apr:", vault.apr());
        vm.stopPrank();
    }

    function testFail_AnulizedInterestLessThanZero() public {
        uint128 tokenAmtIn = 100e8;
        uint128 ftAmtOut = 100e8;
        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);
        vm.expectRevert(VaultErrors.LockedFtGreaterThanTotalFt.selector);
        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, ftAmtOut);
        vm.stopPrank();
    }

    function testFail_LockedFtGreaterThanTotalFt() public {
        vm.warp(currentTime + 2 days);
        buyXt(48.219178e8, 1000e8);
        vm.warp(currentTime + 4 days);
        buyXt(48.219178e8, 1000e8);
        uint128 tokenAmtIn = 100e8;
        uint128 ftAmtOut = 100e8;
        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);
        vm.expectRevert(VaultErrors.LockedFtGreaterThanTotalFt.selector);
        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, ftAmtOut);
        vm.stopPrank();
    }

    function testRedeemFromMarket() public {
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

        vm.startPrank(curator);
        address order2 = address(vault.createOrder(market2, maxCapacity, 0, orderConfig.curveCuts));
        uint[] memory indexes = new uint[](2);
        indexes[0] = 1;
        indexes[1] = 0;
        vault.updateSupplyQueue(indexes);

        res.debt.mint(curator, 10000e8);
        res.debt.approve(address(vault), 10000e8);
        vault.deposit(10000e8, curator);

        vm.stopPrank();

        vm.warp(currentTime + 92 days);

        vm.startPrank(lper2);

        vault.redeem(1000e8, lper2, lper2);
        vm.stopPrank();

        uint performanceFee = vault.performanceFee();
        vm.prank(curator);
        vault.withdrawPerformanceFee(curator, performanceFee);

        assertEq(vault.performanceFee(), 0);
        assertEq(vault.annualizedInterest(), 0);
        assertEq(vault.supplyQueueLength(), 1);
        assertEq(vault.supplyQueue(0), order2);
        assertEq(vault.withdrawQueueLength(), 1);
        assertEq(vault.withdrawQueue(0), order2);

        vm.warp(currentTime + 182 days);
        vm.prank(lper2);
        vault.redeem(1000e8, lper2, lper2);

        vm.prank(curator);
        vault.redeemOrder(ITermMaxOrder(order2));

        assertEq(vault.performanceFee(), 0);
        assertEq(vault.annualizedInterest(), 0);
        assertEq(vault.supplyQueueLength(), 0);
        assertEq(vault.withdrawQueueLength(), 0);
    }

    function testRedeemFromMarket2() public {
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

        vm.startPrank(curator);
        address order2 = address(vault.createOrder(market2, maxCapacity, 0, orderConfig.curveCuts));
        uint[] memory indexes = new uint[](2);
        indexes[0] = 1;
        indexes[1] = 0;
        vault.updateSupplyQueue(indexes);

        res.debt.mint(curator, 10000e8);
        res.debt.approve(address(vault), 10000e8);
        vault.deposit(10000e8, curator);

        vm.stopPrank();

        (, IERC20 xt, , , ) = market2.tokens();

        vm.warp(currentTime + 4 days);
        {
            address taker = vm.randomAddress();
            uint128 tokenAmtIn = 50e8;
            res.debt.mint(taker, tokenAmtIn);
            vm.startPrank(taker);
            res.debt.approve(address(order2), tokenAmtIn);
            ITermMaxOrder(order2).swapExactTokenToToken(res.debt, xt, taker, tokenAmtIn, 1000e8);
            vm.stopPrank();
        }

        vm.warp(currentTime + 92 days);

        {
            address taker = vm.randomAddress();
            uint128 tokenAmtIn = 50e8;
            res.debt.mint(taker, tokenAmtIn);
            vm.startPrank(taker);
            res.debt.approve(address(order2), tokenAmtIn);
            ITermMaxOrder(order2).swapExactTokenToToken(res.debt, xt, taker, tokenAmtIn, 1000e8);
            vm.stopPrank();
        }

        vm.prank(lper2);
        vault.redeem(100e8, lper2, lper2);

        uint performanceFee = vault.performanceFee();
        vm.prank(curator);
        vault.withdrawPerformanceFee(curator, performanceFee);

        assertEq(vault.performanceFee(), 0);
        assertGt(vault.annualizedInterest(), 0);
        assertEq(vault.supplyQueueLength(), 1);
        assertEq(vault.supplyQueue(0), order2);
        assertEq(vault.withdrawQueueLength(), 1);
        assertEq(vault.withdrawQueue(0), order2);

        vm.warp(currentTime + 182 days);
        vm.prank(lper2);
        vault.redeem(100e8, lper2, lper2);

        vm.prank(curator);
        vault.redeemOrder(ITermMaxOrder(order2));

        assertGt(vault.performanceFee(), 0);
        assertEq(vault.annualizedInterest(), 0);
        assertEq(vault.supplyQueueLength(), 0);
        assertEq(vault.withdrawQueueLength(), 0);
    }

    function testBadDebt() public {
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

        address borrower = vm.randomAddress();
        vm.startPrank(borrower);
        LoanUtils.fastMintGt(res, borrower, 1000e8, 1e18);
        vm.stopPrank();

        vm.warp(currentTime + 92 days);

        uint propotion = (res.ft.balanceOf(address(res.order)) * Constants.DECIMAL_BASE_SQ) /
            (res.ft.totalSupply() - res.ft.balanceOf(address(res.market)));

        uint tokenOut = (res.debt.balanceOf(address(res.market)) * propotion) / Constants.DECIMAL_BASE_SQ;
        uint badDebt = res.ft.balanceOf(address(res.order)) - tokenOut;
        uint delivered = (propotion * 1e18) / Constants.DECIMAL_BASE_SQ;

        vm.startPrank(lper2);
        vault.redeem(1000e8, lper2, lper2);
        vm.stopPrank();

        assertEq(vault.badDebtMapping(address(res.collateral)), badDebt);
        assertEq(res.collateral.balanceOf(address(vault)), delivered);

        uint shareToDealBadDebt = vault.previewWithdraw(badDebt / 2);
        vm.startPrank(lper2);
        (uint shares, uint collateralOut) = vault.dealBadDebt(address(res.collateral), badDebt / 2, lper2, lper2);
        assertEq(shares, shareToDealBadDebt);
        assertEq(collateralOut, ((badDebt / 2) * delivered) / badDebt);
        assertEq(vault.badDebtMapping(address(res.collateral)), badDebt - badDebt / 2);
        assertEq(res.collateral.balanceOf(address(vault)), delivered - collateralOut);
        vm.stopPrank();

        vm.startPrank(lper2);
        shareToDealBadDebt = vault.previewWithdraw(badDebt - badDebt / 2);
        uint remainningCollateral = res.collateral.balanceOf(address(vault));
        vm.expectEmit();
        emit VaultEvents.DealBadDebt(
            lper2,
            lper2,
            address(res.collateral),
            badDebt - badDebt / 2,
            shareToDealBadDebt,
            remainningCollateral
        );
        (shares, collateralOut) = vault.dealBadDebt(address(res.collateral), badDebt - badDebt / 2, lper2, lper2);
        assertEq(shares, shareToDealBadDebt);
        assertEq(collateralOut, remainningCollateral);
        assertEq(vault.badDebtMapping(address(res.collateral)), 0);
        assertEq(res.collateral.balanceOf(address(vault)), 0);
        vm.stopPrank();
    }

    function testFail_BadDebt() public {
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

        address borrower = vm.randomAddress();
        vm.startPrank(borrower);
        LoanUtils.fastMintGt(res, borrower, 1000e8, 1e18);
        vm.stopPrank();

        vm.warp(currentTime + 92 days);
        vm.startPrank(lper2);
        vault.redeem(1000e8, lper2, lper2);

        uint256 badDebt = vault.badDebtMapping(address(res.collateral));
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.InsufficientFunds.selector, 1e18, badDebt));
        vault.dealBadDebt(address(res.collateral), 1e18, lper2, lper2);

        vault.dealBadDebt(address(res.collateral), badDebt, lper2, lper2);

        vm.expectRevert(VaultErrors.NoBadDebt.selector);
        vault.dealBadDebt(address(res.collateral), 1e18, lper2, lper2);

        vm.stopPrank();
    }

    function buyFt(uint128 tokenAmtIn, uint128 ftAmtOut) internal {
        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);
        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, ftAmtOut);
        vm.stopPrank();
    }

    function buyXt(uint128 tokenAmtIn, uint128 xtAmtOut) internal {
        address taker = vm.randomAddress();
        res.debt.mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        res.debt.approve(address(res.order), tokenAmtIn);
        res.order.swapExactTokenToToken(res.debt, res.xt, taker, tokenAmtIn, xtAmtOut);
        vm.stopPrank();
    }

    function sellFt(uint128 ftAmtIn, uint128 tokenAmtOut) internal {
        address taker = vm.randomAddress();
        vm.prank(deployer);
        res.ft.transfer(taker, ftAmtIn);
        vm.startPrank(taker);
        res.ft.approve(address(res.order), ftAmtIn);
        res.order.swapExactTokenToToken(res.ft, res.debt, taker, ftAmtIn, tokenAmtOut);
        vm.stopPrank();
    }

    function sellXt(uint128 xtAmtIn, uint128 tokenAmtOut) internal {
        address taker = vm.randomAddress();
        vm.prank(deployer);
        res.xt.transfer(taker, xtAmtIn);
        vm.startPrank(taker);
        res.xt.approve(address(res.order), xtAmtIn);
        res.order.swapExactTokenToToken(res.xt, res.debt, taker, xtAmtIn, tokenAmtOut);
        vm.stopPrank();
    }

    function swapFtToXt(uint128 ftAmtIn, uint128 xtAmtOut) internal {
        address taker = vm.randomAddress();
        vm.prank(deployer);
        res.ft.transfer(taker, ftAmtIn);
        vm.startPrank(taker);
        res.ft.approve(address(res.order), ftAmtIn);
        res.order.swapExactTokenToToken(res.ft, res.xt, taker, ftAmtIn, xtAmtOut);
        vm.stopPrank();
    }

    function swapXtToFt(uint128 xtAmtIn, uint128 ftAmtOut) internal {
        address taker = vm.randomAddress();
        vm.prank(deployer);
        res.xt.transfer(taker, xtAmtIn);
        vm.startPrank(taker);
        res.xt.approve(address(res.order), xtAmtIn);
        res.order.swapExactTokenToToken(res.xt, res.ft, taker, xtAmtIn, ftAmtOut);
        vm.stopPrank();
    }

    function _daysToMaturity(uint256 _now) internal view returns (uint256 daysToMaturity) {
        daysToMaturity =
            (res.market.config().maturity - _now + Constants.SECONDS_IN_DAY - 1) /
            Constants.SECONDS_IN_DAY;
    }
}
