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
    uint64 curatorPercentage = 0.5e8;

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

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

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
                    curatorPercentage
                )
            )
        );
        vault.submitGuardian(guardian);

        vault.submitMarket(address(res.market), true);

        vm.warp(marketConfig.openTime + timelock + 1);
        res.debt.mint(deployer, amount);
        res.debt.approve(address(vault), amount);
        vault.deposit(amount, deployer);
        res.order = vault.createOrder(res.market, orderConfig.maxXtReserve, maxCapacity, amount, orderConfig.curveCuts);

        vm.stopPrank();
    }

    function testRoleManagement() public {
        // Test initial roles
        assertEq(vault.guardian(), guardian);
        assertEq(vault.curator(), curator);
        assertTrue(vault.isAllocator(allocator));

        // Test guardian role checks
        vm.startPrank(guardian);
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
        vm.prank(curator);
        address newAllocator = address(0x789);
        vault.setIsAllocator(newAllocator, true);
        assertTrue(vault.isAllocator(newAllocator));

        vm.prank(curator);
        vault.setIsAllocator(newAllocator, false);
        assertFalse(vault.isAllocator(newAllocator));
    }

    function testMarketWhitelist() public {
        address market = address(0x123);

        // Non-guardian should not be able to whitelist
        vm.prank(lper);
        vm.expectRevert();
        vault.submitMarket(market, true);

        // Guardian can submit market
        vm.prank(guardian);
        vault.submitMarket(market, true);

        // Should not be whitelisted before timelock
        assertFalse(vault.marketWhitelist(market));

        // After timelock passes
        vm.warp(block.timestamp + timelock + 1);
        vm.prank(guardian);
        vault.acceptMarket(market);
        assertTrue(vault.marketWhitelist(market));

        // Can revoke pending market
        vm.prank(guardian);
        vault.submitMarket(market, false);
        vm.warp(block.timestamp + timelock + 1);
        vm.prank(guardian);
        vault.acceptMarket(market);
        assertFalse(vault.marketWhitelist(market));
    }

    function testTimelockManagement() public {
        uint256 newTimelock = 2 days;

        // Only guardian can submit new timelock
        vm.prank(lper);
        vm.expectRevert();
        vault.submitTimelock(newTimelock);

        vm.prank(guardian);
        vault.submitTimelock(newTimelock);

        // Cannot accept before timelock period
        vm.warp(block.timestamp + timelock / 2);
        vm.prank(guardian);
        vm.expectRevert();
        vault.acceptTimelock();

        // Can accept after timelock period
        vm.warp(block.timestamp + timelock + 1);
        vm.prank(guardian);
        vault.acceptTimelock();
        assertEq(vault.timelock(), newTimelock);

        // Can revoke pending timelock
        vm.prank(guardian);
        vault.submitTimelock(3 days);
        vm.prank(guardian);
        vault.revokePendingTimelock();

        // After revoking, should not be able to accept
        vm.warp(block.timestamp + timelock + 1);
        vm.prank(guardian);
        vm.expectRevert();
        vault.acceptTimelock();
    }

    function testCuratorPercentage() public {
        uint184 newPercentage = 0.4e8;

        vm.prank(curator);
        vault.submitCuratorPercentage(newPercentage);

        uint percentage = vault.curatorPercentage();
        assertEq(percentage, newPercentage);

        // (uint192 curPercentage, ) = vault.pendingCuratorPercentage();
        // assertEq(uint256(curPercentage), newPercentage);

        // vm.warp(block.timestamp + timelock + 1);
        // vm.prank(vm.randomAddress());
        // vault.acceptCuratorPercentage();
        // uint percentage = vault.curatorPercentage();
        // assertEq(percentage, newPercentage);
    }

    function testDeposit() public {
        uint256 depositAmount = 1000e8;
        MockERC20 asset = res.debt;

        // Mint tokens to lper
        asset.mint(lper, depositAmount);

        vm.startPrank(lper);
        asset.approve(address(vault), depositAmount);

        // Test deposit
        uint256 sharesBefore = vault.balanceOf(lper);
        vault.deposit(depositAmount, lper);
        uint256 sharesAfter = vault.balanceOf(lper);

        assertEq(sharesAfter - sharesBefore, depositAmount);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        vm.stopPrank();
    }

    function testWithdraw() public {
        uint256 depositAmount = 1000e8;
        MockERC20 asset = res.debt;

        // Setup: deposit first
        asset.mint(lper, depositAmount);
        vm.startPrank(lper);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, lper);

        // Test withdraw
        uint256 balanceBefore = asset.balanceOf(lper);
        vault.withdraw(depositAmount, lper, lper);
        uint256 balanceAfter = asset.balanceOf(lper);

        assertEq(balanceAfter - balanceBefore, depositAmount);
        assertEq(vault.balanceOf(lper), 0);
        vm.stopPrank();
    }
}
