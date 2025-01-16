// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFlashLoanReceiver} from "contracts/IFlashLoanReceiver.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, MarketEvents, MarketErrors} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder, TermMaxOrder, ISwapCallback, OrderEvents, OrderErrors} from "contracts/TermMaxOrder.sol";
import {MockERC20, ERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {TermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {BaseVault, VaultErrors, VaultEvents, ITermMaxVault} from "contracts/vault/BaseVault.sol";
import {VaultConstants} from "contracts/lib/VaultConstants.sol";
import {VaultFactory} from "contracts/factory/VaultFactory.sol";
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

    TermMaxVault vault;

    uint timelock = 86400;
    uint maxCapacity = 10000e8;
    uint64 maxTerm = 90 days;
    uint64 performanceFeeRate = 0.5e8;

    uint currentTime;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));
        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");
        vm.warp(marketConfig.openTime);
        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        // res.order = res.market.createOrder(
        //     maker,
        //     orderConfig.maxXtReserve,
        //     ISwapCallback(address(0)),
        //     orderConfig.curveCuts
        // );
        currentTime = vm.parseUint(vm.parseJsonString(testdata, ".currentTime"));
        vm.warp(currentTime);

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth")
        );
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        uint amount = 150e8;

        VaultFactory vaultFactory = new VaultFactory();
        vault = TermMaxVault(
            vaultFactory.createVault(
                VaultInitialParams(
                    deployer,
                    curator,
                    timelock,
                    res.debt,
                    maxCapacity,
                    "Vault-DAI",
                    "Vault-DAI",
                    maxTerm,
                    performanceFeeRate
                )
            )
        );
        vault.submitGuardian(guardian);

        vault.submitMarket(address(res.market), true);
        vault.setIsAllocator(allocator, true);

        vm.warp(marketConfig.openTime + timelock + 1);
        res.debt.mint(deployer, amount);
        res.debt.approve(address(vault), amount);
        vault.deposit(amount, deployer);
        res.order = vault.createOrder(res.market, maxCapacity, amount, orderConfig.curveCuts);

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

    function testTimelockManagement() public {
        uint256 newTimelock = 2 days;

        vm.prank(curator);
        vault.submitTimelock(newTimelock);
        assertEq(vault.timelock(), newTimelock);

        newTimelock = 1.5 days;
        vm.prank(curator);
        vault.submitTimelock(newTimelock);
        assertEq(vault.timelock(), 2 days);

        (uint192 pendingTimelock, uint64 pendingTimelockValidAt) = vault.pendingTimelock();
        assertEq(uint256(pendingTimelock), newTimelock);
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

        (uint192 curPercentage, uint64 validAt) = vault.pendingPerformanceFeeRate();
        assertEq(uint256(curPercentage), newPercentage);

        vm.warp(validAt);
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

    // function testDeposit() public {
    //     uint256 depositAmount = 1000e8;
    //     MockERC20 asset = res.debt;

    //     // Mint tokens to lper
    //     asset.mint(lper, depositAmount);

    //     vm.startPrank(lper);
    //     asset.approve(address(vault), depositAmount);

    //     // Test deposit
    //     uint256 sharesBefore = vault.balanceOf(lper);
    //     vault.deposit(depositAmount, lper);
    //     uint256 sharesAfter = vault.balanceOf(lper);

    //     assertEq(sharesAfter - sharesBefore, depositAmount);
    //     assertEq(asset.balanceOf(address(vault)), depositAmount);
    //     vm.stopPrank();
    // }

    // function testWithdraw() public {
    //     uint256 depositAmount = 1000e8;
    //     MockERC20 asset = res.debt;

    //     // Setup: deposit first
    //     asset.mint(lper, depositAmount);
    //     vm.startPrank(lper);
    //     asset.approve(address(vault), depositAmount);
    //     vault.deposit(depositAmount, lper);

    //     // Test withdraw
    //     uint256 balanceBefore = asset.balanceOf(lper);
    //     vault.withdraw(depositAmount, lper, lper);
    //     uint256 balanceAfter = asset.balanceOf(lper);

    //     assertEq(balanceAfter - balanceBefore, depositAmount);
    //     assertEq(vault.balanceOf(lper), 0);
    //     vm.stopPrank();
    // }
}
