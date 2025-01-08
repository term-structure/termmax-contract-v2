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
import {IFlashLoanReceiver} from "contracts/IFlashLoanReceiver.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, MarketEvents, MarketErrors} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder, TermMaxOrder, ISwapCallback, OrderEvents} from "contracts/TermMaxOrder.sol";
import {MockERC20, ERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";
import "contracts/storage/TermMaxStorage.sol";

contract MarketTest is Test {
    using JSONLoader for *;
    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address maker = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");
        vm.warp(marketConfig.openTime);
        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order = res.market.createOrder(
            maker,
            orderConfig.maxXtReserve,
            ISwapCallback(address(0)),
            orderConfig.curveCuts
        );

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth")
        );
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        vm.stopPrank();
    }

    function testUpdateMarketConfig() public {
        vm.startPrank(deployer);
        marketConfig.treasurer = vm.randomAddress();
        marketConfig.feeConfig.redeemFeeRatio = 0.01e8;
        marketConfig.feeConfig.issueFtFeeRatio = 0.02e8;
        marketConfig.feeConfig.borrowTakerFeeRatio = 0.03e8;
        marketConfig.feeConfig.borrowMakerFeeRatio = 0.04e8;
        marketConfig.feeConfig.lendTakerFeeRatio = 0.05e8;
        marketConfig.feeConfig.lendMakerFeeRatio = 0.06e8;

        vm.expectEmit();
        emit MarketEvents.UpdateMarketConfig(marketConfig);
        res.market.updateMarketConfig(marketConfig);

        assertEq(res.market.config().treasurer, marketConfig.treasurer);
        assertEq(res.market.config().feeConfig.redeemFeeRatio, marketConfig.feeConfig.redeemFeeRatio);
        assertEq(res.market.config().feeConfig.issueFtFeeRatio, marketConfig.feeConfig.issueFtFeeRatio);
        assertEq(res.market.config().feeConfig.borrowTakerFeeRatio, marketConfig.feeConfig.borrowTakerFeeRatio);
        assertEq(res.market.config().feeConfig.borrowMakerFeeRatio, marketConfig.feeConfig.borrowMakerFeeRatio);
        assertEq(res.market.config().feeConfig.lendTakerFeeRatio, marketConfig.feeConfig.lendTakerFeeRatio);
        assertEq(res.market.config().feeConfig.lendMakerFeeRatio, marketConfig.feeConfig.lendMakerFeeRatio);

        vm.stopPrank();
    }

    function testMint() public {
        vm.startPrank(sender);
        uint amount = 150e8;
        res.debt.mint(sender, amount);
        res.debt.approve(address(res.market), amount);

        emit MarketEvents.Mint(sender, sender, amount);
        res.market.mint(sender, amount);

        assertEq(res.debt.balanceOf(sender), 0);
        assertEq(res.ft.balanceOf(sender), amount);
        assertEq(res.xt.balanceOf(sender), amount);
        assertEq(res.debt.balanceOf(address(res.market)), amount);

        vm.stopPrank();
    }

    function testMintWhenTermIsNotOpen() public {
        vm.startPrank(sender);
        uint amount = 150e8;
        res.debt.mint(sender, amount);
        res.debt.approve(address(res.market), amount);
        vm.warp(marketConfig.openTime - 1);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.mint(sender, amount);

        vm.warp(marketConfig.maturity);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.mint(sender, amount);

        vm.stopPrank();
    }

    function testBurn() public {
        vm.startPrank(sender);
        uint amount = 150e8;
        res.debt.mint(sender, amount);
        res.debt.approve(address(res.market), amount);
        res.market.mint(sender, amount);

        res.ft.approve(address(res.market), amount);
        res.xt.approve(address(res.market), amount);
        emit MarketEvents.Burn(sender, sender, amount);
        res.market.burn(sender, amount);
        assertEq(res.debt.balanceOf(sender), amount);
        assertEq(res.ft.balanceOf(sender), 0);
        assertEq(res.xt.balanceOf(sender), 0);
        assertEq(res.debt.balanceOf(address(res.market)), 0);
        vm.stopPrank();
    }

    function testBurnWhenTermIsNotOpen() public {
        vm.startPrank(sender);
        uint amount = 150e8;
        res.debt.mint(sender, amount);
        res.debt.approve(address(res.market), amount);
        vm.warp(marketConfig.openTime - 1);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.burn(sender, amount);

        vm.warp(marketConfig.maturity);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.burn(sender, amount);
        vm.stopPrank();
    }

    function testIssueFt() public {
        vm.startPrank(sender);
        uint128 debtAmt = 1000e8;
        res.debt.mint(sender, debtAmt);
        res.debt.approve(address(res.market), debtAmt);
        res.market.mint(sender, debtAmt);

        uint fee = (res.market.issueFtFeeRatio() * debtAmt) / Constants.DECIMAL_BASE;
        uint collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        vm.expectEmit();
        emit MarketEvents.IssueFt(
            sender,
            sender,
            1,
            debtAmt,
            uint128(debtAmt - fee),
            uint128(fee),
            abi.encode(collateralAmt)
        );
        (uint gtId, uint128 ftOutAmt) = res.market.issueFt(sender, debtAmt, abi.encode(collateralAmt));

        assertEq(gtId, 1);
        assertEq(res.debt.balanceOf(sender), 0);
        assertEq(debtAmt - fee, ftOutAmt);
        assertEq(res.ft.balanceOf(sender), ftOutAmt + debtAmt);
        assertEq(res.collateral.balanceOf(address(res.gt)), collateralAmt);
        assertEq(res.debt.balanceOf(address(res.market)), debtAmt);

        (address owner, uint128 dAmt, , bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(dAmt, debtAmt);

        assertEq(abi.decode(collateralData, (uint256)), collateralAmt);

        vm.stopPrank();
    }

    function testIssueFtWhenTermIsNotOpen() public {
        vm.startPrank(sender);
        uint128 debtAmt = 1000e8;
        vm.warp(marketConfig.openTime - 1);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.issueFt(sender, debtAmt, abi.encode(1e18));

        vm.warp(marketConfig.maturity);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.issueFt(sender, debtAmt, abi.encode(1e18));
        vm.stopPrank();
    }

    function testCreateOrder() public {
        vm.startPrank(sender);

        vm.expectEmit();
        emit OrderEvents.OrderInitialized(
            res.market,
            sender,
            orderConfig.maxXtReserve,
            ISwapCallback(address(0)),
            orderConfig.curveCuts
        );
        ITermMaxOrder order = res.market.createOrder(
            sender,
            orderConfig.maxXtReserve,
            ISwapCallback(address(0)),
            orderConfig.curveCuts
        );
        assertEq(address(order.market()), address(res.market));
        assertEq(Ownable(address(order)).owner(), Ownable(address(res.market)).owner());
        assertEq(order.orderConfig().maxXtReserve, orderConfig.maxXtReserve);
        assertEq(order.maker(), sender);

        vm.stopPrank();
    }
}
