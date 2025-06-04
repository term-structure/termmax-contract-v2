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
import {IFlashLoanReceiver} from "contracts/v1/IFlashLoanReceiver.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, MarketEvents, MarketErrors} from "contracts/v1/TermMaxMarket.sol";
import {ITermMaxOrder, TermMaxOrder, ISwapCallback, OrderEvents, OrderErrors} from "contracts/v1/TermMaxOrder.sol";
import {MockERC20, ERC20} from "contracts/v1/test/MockERC20.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {TermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {VaultErrors, VaultEvents, ITermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {OrderManager, OrderInfo} from "contracts/v1/vault/OrderManager.sol";
import {VaultConstants} from "contracts/v1/lib/VaultConstants.sol";
import {PendingAddress, PendingUint192} from "contracts/v1/lib/PendingLib.sol";
import "contracts/v1/storage/TermMaxStorage.sol";

contract VaultDustTest is Test {
    using JSONLoader for *;
    using SafeCast for *;

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

    uint256 timelock = 86400;
    uint256 maxCapacity = 1000000e18;
    uint64 performanceFeeRate = 0.1e8;

    ITermMaxMarket market2;

    uint256 currentTime;
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;
    VaultInitialParams initialParams;

    DeployUtils.Res[] resources;

    address bob = vm.addr(0x123);
    address alice = vm.addr(0x456);
    address charlie = vm.addr(0x789);

    address[] users = [bob, alice, charlie];

    uint256[] durations = [3, 4, 10, 20, 5, 5, 3, 15, 20, 12];

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        currentTime = vm.parseUint(vm.parseJsonString(testdata, ".currentTime"));
        vm.warp(currentTime);

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        MockERC20 debt = new MockERC20("DAI", "DAI", 6);
        for (uint256 i = 0; i < 10; i++) {
            resources.push(
                DeployUtils.deployMockMarket2(deployer, debt, durations[i], marketConfig, maxLtv, liquidationLtv)
            );
        }

        initialParams = VaultInitialParams(
            deployer, curator, timelock, debt, maxCapacity, "Vault-DAI", "Vault-DAI", performanceFeeRate
        );

        vault = DeployUtils.deployVault(initialParams);

        vault.submitGuardian(guardian);
        vault.setIsAllocator(allocator, true);

        for (uint256 i = 0; i < resources.length; i++) {
            address market = address(resources[i].market);
            vault.submitMarket(market, true);
            vm.warp(currentTime + timelock + 1);
            vault.acceptMarket(market);
            vm.warp(currentTime);
        }

        vm.stopPrank();

        debt.mint(bob, 10000e16);
        vm.startPrank(bob);
        debt.approve(address(vault), maxCapacity);
        vault.deposit(10000e16 / 2, bob);
        vm.stopPrank();

        vm.startPrank(alice);
        debt.mint(alice, 5000e18);
        debt.approve(address(vault), maxCapacity);
        vault.deposit(5000e18 / 2, alice);
        vm.stopPrank();

        vm.startPrank(charlie);
        debt.mint(charlie, 20e15);
        debt.approve(address(vault), maxCapacity);
        vault.deposit(20e15 / 2, charlie);
        vm.stopPrank();

        for (uint256 i = 0; i < resources.length; i++) {
            vm.startPrank(deployer);
            ITermMaxMarket market = resources[i].market;
            resources[i].order = vault.createOrder(market, maxCapacity, i * 1e15, orderConfig.curveCuts);
            vm.stopPrank();
        }
    }

    function testDust() public {
        uint256 count = 0;
        while (block.timestamp < currentTime + 30 days) {
            uint256 k = vm.randomUint(2 ** 128 - 1, 2 ** 256 - 1);
            uint256 period = vm.randomUint(2000, 3600);
            count++;
            vm.warp(block.timestamp);
            uint256 i = k % 10;
            // ITermMaxMarket market = resources[i].market;
            ITermMaxOrder order = resources[i].order;
            uint256 amount = k % 1e4;
            // (, uint256 borrowApr) = order.apr();
            // uint256 virturalApr = borrowApr * (block.timestamp - currentTime) / 365 days;
            uint256 ftBalance = resources[i].ft.balanceOf(address(order));
            uint256 xtBalance = resources[i].xt.balanceOf(address(order));

            if (xtBalance < ftBalance * 8 / 10 && amount * 2 < ftBalance) {
                console.log("buy ft:", amount);
                buyFt(order, uint128(amount), uint128(amount * 2));
            } else if (amount * 2 < xtBalance) {
                console.log("buy xt:", amount);
                buyXt(order, uint128(amount), uint128(amount * 2));
            }

            if (i < 3) {
                vm.prank(users[i]);
                if (block.timestamp % 2 == 0) {
                    console.log("redeem:", i);
                    vault.redeem(1e5, users[i], users[i]);
                } else {
                    console.log("deposit:", i);
                    vault.deposit(1e5, users[i]);
                }
            }

            vm.warp(block.timestamp + period);
        }
        vm.warp(block.timestamp + 60 days);
        console.log("---- do redeem ---");
        for (uint256 i = 0; i < resources.length; i++) {
            vm.prank(curator);
            vault.redeemOrder(resources[i].order);
        }
        uint256 performanceFee = vault.performanceFee();
        console.log("performanceFee:", performanceFee);
        vm.prank(curator);
        vault.withdrawPerformanceFee(curator, performanceFee);

        vm.warp(block.timestamp + 10);
        console.log("---- status ---");
        console.log("run count:", count);
        console.log("total assets:", vault.totalAssets());
        console.log("total supply:", vault.totalSupply());
        console.log("annualizedInterest:", vault.annualizedInterest());
        console.log("apr:", vault.apr());
        console.log("total ft:", vault.totalFt());
        console.log("actual balance:", resources[0].debt.balanceOf(address(vault)));
        console.log("accretingPrincipal:", vault.accretingPrincipal());

        console.log("---- do redeem ---");
        console.log("asset:", address(resources[0].debt));
        console.log("vault:", address(vault));
        for (uint256 i = 0; i < resources.length; i++) {
            address collateral = address(resources[i].collateral);
            if (vault.badDebtMapping(collateral) > 0) {
                console.log("badDebt:", vault.badDebtMapping(collateral));
                console.log("collateral:", collateral);
            }
        }
        for (uint256 i = 0; i < users.length; i++) {
            console.log("user i:", i);
            console.log("balance:", vault.balanceOf(users[i]));
            vm.startPrank(users[i]);
            uint256 redeemed = vault.redeem(vault.balanceOf(users[i]), users[i], users[i]);
            console.log("redeemed:", redeemed);
            console.log("remainning total assets:", vault.totalAssets());
            vm.stopPrank();
        }
        uint256 dustAmt = resources[0].debt.balanceOf(address(vault));
        console.log("remaining balance:", dustAmt);
        assertLe(dustAmt, 3);
    }

    function buyFt(ITermMaxOrder order, uint128 tokenAmtIn, uint128 ftAmtOut) internal {
        address taker = vm.randomAddress();
        (IMintableERC20 ft, IMintableERC20 xt,,, IERC20 debt) = order.market().tokens();
        IMintableERC20(address(debt)).mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        debt.approve(address(order), tokenAmtIn);
        order.swapExactTokenToToken(debt, ft, taker, tokenAmtIn, ftAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function buyXt(ITermMaxOrder order, uint128 tokenAmtIn, uint128 xtAmtOut) internal {
        address taker = vm.randomAddress();
        (IMintableERC20 ft, IMintableERC20 xt,,, IERC20 debt) = order.market().tokens();
        IMintableERC20(address(debt)).mint(taker, tokenAmtIn);
        vm.startPrank(taker);
        debt.approve(address(order), tokenAmtIn);
        order.swapExactTokenToToken(debt, xt, taker, tokenAmtIn, xtAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function sellFt(ITermMaxOrder order, uint128 ftAmtIn, uint128 tokenAmtOut) internal {
        address taker = vm.randomAddress();
        (IMintableERC20 ft, IMintableERC20 xt,,, IERC20 debt) = order.market().tokens();
        vm.prank(deployer);
        ft.transfer(taker, ftAmtIn);
        vm.startPrank(taker);
        ft.approve(address(order), ftAmtIn);
        order.swapExactTokenToToken(ft, debt, taker, ftAmtIn, tokenAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function sellXt(ITermMaxOrder order, uint128 xtAmtIn, uint128 tokenAmtOut) internal {
        address taker = vm.randomAddress();
        (IMintableERC20 ft, IMintableERC20 xt,,, IERC20 debt) = order.market().tokens();
        vm.prank(deployer);
        xt.transfer(taker, xtAmtIn);
        vm.startPrank(taker);
        xt.approve(address(order), xtAmtIn);
        order.swapExactTokenToToken(xt, debt, taker, xtAmtIn, tokenAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }
}
