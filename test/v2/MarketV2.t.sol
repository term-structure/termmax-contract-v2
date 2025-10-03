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
import {IFlashLoanReceiver} from "contracts/v1/IFlashLoanReceiver.sol";
import {
    ITermMaxMarketV2, TermMaxMarketV2, Constants, MarketErrors, MarketEvents
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
    CurveCuts
} from "contracts/v1/storage/TermMaxStorage.sol";
import {OrderEventsV2} from "contracts/v2/events/OrderEventsV2.sol";
import {TermMaxOrderV2} from "contracts/v2/TermMaxOrderV2.sol";
import {OrderInitialParams} from "contracts/v2/storage/TermMaxStorageV2.sol";

contract MarketV2Test is Test {
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
        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order = TermMaxOrderV2(
            address(
                res.market.createOrder(
                    maker, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts
                )
            )
        );

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        vm.stopPrank();
    }

    function testUpdateMarketConfig() public {
        vm.startPrank(deployer);
        marketConfig.treasurer = vm.randomAddress();
        marketConfig.feeConfig.mintGtFeeRatio = 0.02e8;
        marketConfig.feeConfig.borrowTakerFeeRatio = 0.03e8;
        marketConfig.feeConfig.borrowMakerFeeRatio = 0.04e8;
        marketConfig.feeConfig.lendTakerFeeRatio = 0.05e8;
        marketConfig.feeConfig.lendMakerFeeRatio = 0.06e8;

        vm.expectEmit();
        emit MarketEvents.UpdateMarketConfig(marketConfig);
        res.market.updateMarketConfig(marketConfig);

        assertEq(res.market.config().treasurer, marketConfig.treasurer);
        assertEq(res.gt.getGtConfig().treasurer, marketConfig.treasurer);
        assertEq(res.market.config().feeConfig.mintGtFeeRatio, marketConfig.feeConfig.mintGtFeeRatio);
        assertEq(res.market.config().feeConfig.borrowTakerFeeRatio, marketConfig.feeConfig.borrowTakerFeeRatio);
        assertEq(res.market.config().feeConfig.borrowMakerFeeRatio, marketConfig.feeConfig.borrowMakerFeeRatio);
        assertEq(res.market.config().feeConfig.lendTakerFeeRatio, marketConfig.feeConfig.lendTakerFeeRatio);
        assertEq(res.market.config().feeConfig.lendMakerFeeRatio, marketConfig.feeConfig.lendMakerFeeRatio);

        vm.stopPrank();
    }

    function testUpdateMarketConfigWhenNotOwner() public {
        vm.startPrank(sender);
        marketConfig.treasurer = vm.randomAddress();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(sender)));
        res.market.updateMarketConfig(marketConfig);
        vm.stopPrank();
    }

    function testUpdateOrderConfigInvalidParams() public {
        vm.startPrank(deployer);

        MarketConfig memory newConfig = res.market.config();
        newConfig.feeConfig.mintGtFeeRef = uint32(Constants.DECIMAL_BASE * 5 + 1);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.FeeTooHigh.selector));
        res.market.updateMarketConfig(newConfig);

        newConfig.feeConfig.mintGtFeeRef = 0;
        newConfig.feeConfig.borrowMakerFeeRatio = uint32(Constants.MAX_FEE_RATIO);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.FeeTooHigh.selector));
        res.market.updateMarketConfig(newConfig);
        vm.stopPrank();
    }

    function testMint() public {
        vm.startPrank(sender);
        uint256 amount = 150e8;
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
        uint256 amount = 150e8;
        res.debt.mint(sender, amount);
        res.debt.approve(address(res.market), amount);

        vm.warp(marketConfig.maturity);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.mint(sender, amount);

        vm.stopPrank();
    }

    function testBurn() public {
        vm.startPrank(sender);
        uint256 amount = 150e8;
        res.debt.mint(sender, amount);
        res.debt.approve(address(res.market), amount);
        res.market.mint(sender, amount);

        emit MarketEvents.Burn(sender, sender, amount);
        ITermMaxMarketV2(address(res.market)).burn(sender, sender, amount);
        assertEq(res.debt.balanceOf(sender), amount);
        assertEq(res.ft.balanceOf(sender), 0);
        assertEq(res.xt.balanceOf(sender), 0);
        assertEq(res.debt.balanceOf(address(res.market)), 0);
        vm.stopPrank();
    }

    function testBurnWhenTermIsNotOpen() public {
        vm.startPrank(sender);
        uint256 amount = 150e8;
        res.debt.mint(sender, amount);
        res.debt.approve(address(res.market), amount);
        vm.warp(marketConfig.maturity);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        ITermMaxMarketV2(address(res.market)).burn(sender, sender, amount);
        vm.stopPrank();
    }

    function testIssueFt() public {
        vm.startPrank(sender);
        uint128 debtAmt = 1000e8;
        res.debt.mint(sender, debtAmt);
        res.debt.approve(address(res.market), debtAmt);
        res.market.mint(sender, debtAmt);

        uint256 fee = (res.market.mintGtFeeRatio() * debtAmt) / Constants.DECIMAL_BASE;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        vm.expectEmit();
        emit MarketEvents.IssueFt(
            sender, sender, 1, debtAmt, uint128(debtAmt - fee), uint128(fee), abi.encode(collateralAmt)
        );
        (uint256 gtId, uint128 ftOutAmt) = res.market.issueFt(sender, debtAmt, abi.encode(collateralAmt));

        assertEq(gtId, 1);
        assertEq(res.debt.balanceOf(sender), 0);
        assertEq(debtAmt - fee, ftOutAmt);
        assertEq(res.ft.balanceOf(sender), ftOutAmt + debtAmt);
        assertEq(res.collateral.balanceOf(address(res.gt)), collateralAmt);
        assertEq(res.debt.balanceOf(address(res.market)), debtAmt);

        (address owner, uint128 dAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(dAmt, debtAmt);

        assertEq(abi.decode(collateralData, (uint256)), collateralAmt);

        vm.stopPrank();
    }

    function testIssueFtByExistGt() public {
        vm.startPrank(sender);
        uint128 debtAmt = 1000e8;

        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        (uint256 gtId, uint128 ftOutAmt) = res.market.issueFt(sender, debtAmt, abi.encode(collateralAmt));

        uint128 debtAmt2 = debtAmt / 2;
        uint256 fee = (res.market.mintGtFeeRatio() * debtAmt2) / Constants.DECIMAL_BASE;
        vm.expectEmit();
        emit MarketEvents.IssueFtByExistedGt(sender, sender, gtId, debtAmt2, uint128(debtAmt2 - fee), uint128(fee));
        uint256 ftOutAmt2 = res.market.issueFtByExistedGt(sender, debtAmt2, gtId);

        assertEq(res.ft.balanceOf(sender), ftOutAmt + ftOutAmt2);
        (address owner, uint128 dAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(dAmt, debtAmt + debtAmt2);
        assertEq(abi.decode(collateralData, (uint256)), collateralAmt);
        vm.stopPrank();
    }

    function testIssueFtByExistedGtWhenTermIsNotOpen() public {
        vm.startPrank(sender);
        uint128 debtAmt = 1000e8;

        vm.warp(marketConfig.maturity);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.issueFtByExistedGt(sender, debtAmt, 1);
        vm.stopPrank();
    }

    function testIssueFtWhenTermIsNotOpen() public {
        vm.startPrank(sender);
        uint128 debtAmt = 1000e8;

        vm.warp(marketConfig.maturity);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.issueFt(sender, debtAmt, abi.encode(1e18));
        vm.stopPrank();
    }

    function testLeverage() public {
        uint128 xtAmt = 1000e8;
        uint256 collateralAmt = 1e18;
        vm.startPrank(deployer);
        res.debt.mint(deployer, xtAmt);
        res.debt.approve(address(res.market), xtAmt);
        res.market.mint(deployer, xtAmt);
        res.xt.transfer(sender, xtAmt);
        vm.stopPrank();

        vm.startPrank(sender);
        MockFlashLoanReceiver receiver = new MockFlashLoanReceiver(res.market);
        res.xt.approve(address(receiver), xtAmt);

        res.collateral.mint(address(receiver), collateralAmt);

        uint256 debtAmt = xtAmt * Constants.DECIMAL_BASE / (Constants.DECIMAL_BASE - res.market.mintGtFeeRatio());

        vm.expectEmit();
        emit MarketEvents.LeverageByXt(
            address(receiver), sender, 1, uint128(debtAmt), xtAmt, uint128(debtAmt - xtAmt), abi.encode(collateralAmt)
        );
        receiver.leverageByXt(xtAmt, abi.encode(sender, collateralAmt));

        assertEq(res.debt.balanceOf(sender), 0);
        assertEq(res.debt.balanceOf(address(res.market)), 0);
        assertEq(res.debt.balanceOf(address(receiver)), xtAmt);
        assertEq(res.xt.balanceOf(sender), 0);

        (address owner, uint128 dAmt, bytes memory collateralData) = res.gt.loanInfo(1);
        assertEq(owner, sender);

        assertEq(dAmt, uint128(debtAmt));

        assertEq(abi.decode(collateralData, (uint256)), collateralAmt);

        vm.stopPrank();
    }

    function testLeverageWhenTermIsNotOpen() public {
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;
        vm.startPrank(deployer);
        res.debt.mint(deployer, debtAmt);
        res.debt.approve(address(res.market), debtAmt);
        res.market.mint(deployer, debtAmt);
        res.xt.transfer(sender, debtAmt);
        vm.stopPrank();

        vm.startPrank(sender);
        MockFlashLoanReceiver receiver = new MockFlashLoanReceiver(res.market);
        res.xt.approve(address(receiver), debtAmt);

        vm.warp(marketConfig.maturity);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        receiver.leverageByXt(debtAmt, abi.encode(sender, collateralAmt));
        vm.stopPrank();
    }

    function testCreateOrder() public {
        vm.startPrank(sender);
        orderConfig.feeConfig = res.market.config().feeConfig;
        vm.expectEmit();
        emit OrderEventsV2.OrderInitialized(sender, address(res.market));
        ITermMaxOrder order =
            res.market.createOrder(sender, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts);
        assertEq(address(order.market()), address(res.market));
        assertEq(Ownable(address(order)).owner(), sender);
        assertEq(order.orderConfig().maxXtReserve, orderConfig.maxXtReserve);
        assertEq(order.maker(), sender);

        vm.stopPrank();
    }

    function testCreateOrderWhenTermIsNotOpen() public {
        vm.startPrank(sender);
        vm.warp(marketConfig.maturity);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.TermIsNotOpen.selector));
        res.market.createOrder(sender, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts);
        vm.stopPrank();
    }

    function testRedeem() public {
        address bob = vm.randomAddress();
        address alice = vm.randomAddress();

        uint128 depositAmt = 1000e8;
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(bob);
        res.debt.mint(bob, depositAmt);
        res.debt.approve(address(res.market), depositAmt);
        res.market.mint(bob, depositAmt);

        res.xt.transfer(alice, debtAmt);
        vm.stopPrank();

        vm.startPrank(alice);

        MockFlashLoanReceiver receiver = new MockFlashLoanReceiver(res.market);
        res.collateral.mint(address(receiver), collateralAmt);

        res.xt.approve(address(receiver), debtAmt);
        receiver.leverageByXt(debtAmt, abi.encode(alice, collateralAmt));
        uint128 leverageFee =
            uint128(debtAmt * Constants.DECIMAL_BASE / (Constants.DECIMAL_BASE - res.market.mintGtFeeRatio())) - debtAmt;
        vm.stopPrank();

        vm.warp(marketConfig.maturity + Constants.LIQUIDATION_WINDOW);

        vm.startPrank(bob);
        res.ft.approve(address(res.market), depositAmt);

        (uint256 expectDebt, bytes memory collateralData) = res.market.previewRedeem(depositAmt);
        vm.expectEmit();
        uint128 proportion = uint128(Constants.DECIMAL_BASE_SQ) * depositAmt / (depositAmt + leverageFee);
        emit MarketEvents.Redeem(bob, bob, proportion, uint128(expectDebt), collateralData);
        ITermMaxMarketV2(address(res.market)).redeem(bob, bob, depositAmt);
        uint256 expectCollateral = abi.decode(collateralData, (uint256));

        assertEq(res.debt.balanceOf(bob), expectDebt);
        assertEq(res.collateral.balanceOf(bob), expectCollateral);
        assertEq(res.debt.balanceOf(address(res.market)), (depositAmt - debtAmt) - expectDebt);
        assertEq(res.collateral.balanceOf(address(res.gt)), collateralAmt - expectCollateral);
        assertEq(res.ft.balanceOf(bob), 0);
        vm.stopPrank();
    }

    function testRedeemBeforeDeadline() public {
        uint128 depositAmt = 1000e8;

        vm.startPrank(sender);
        res.debt.mint(sender, depositAmt);
        res.debt.approve(address(res.market), depositAmt);
        res.market.mint(sender, depositAmt);

        res.ft.approve(address(res.market), depositAmt);
        uint256 deadline = marketConfig.maturity + Constants.LIQUIDATION_WINDOW;
        vm.warp(deadline - 1);
        vm.expectRevert(
            abi.encodeWithSelector(MarketErrors.CanNotRedeemBeforeFinalLiquidationDeadline.selector, deadline)
        );
        ITermMaxMarketV2(address(res.market)).redeem(sender, sender, depositAmt);

        vm.warp(marketConfig.maturity - 1);
        vm.expectRevert(
            abi.encodeWithSelector(MarketErrors.CanNotRedeemBeforeFinalLiquidationDeadline.selector, deadline)
        );
        ITermMaxMarketV2(address(res.market)).redeem(sender, sender, depositAmt);

        vm.stopPrank();
    }

    function testFuzzIssueFtByExistedGtDebtAmount(uint128 issueAmount) public {
        vm.assume(issueAmount >= 1);
        vm.assume(issueAmount <= type(uint64).max);

        uint128 debt =
            uint128((issueAmount * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - res.market.mintGtFeeRatio()));

        vm.startPrank(sender);

        uint256 collateralAmt = type(uint128).max;
        bytes memory collateralData = abi.encode(collateralAmt);
        res.collateral.mint(sender, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        res.market.issueFt(sender, issueAmount, collateralData);

        uint128 ftOutAmt = res.market.issueFtByExistedGt(sender, debt, 1);
        assertTrue(ftOutAmt == issueAmount);
        vm.stopPrank();
    }

    // Test deterministic clone prediction and creation with salt
    function testPredictAndCreateOrderWithSalt() public {
        vm.startPrank(sender);

        // prepare OrderInitialParams with maker and orderConfig; other fields are set by market during initialization
        OrderInitialParams memory params;
        params.maker = sender;
        params.orderConfig = orderConfig;

        uint256 salt = 0xfeedbeef;

        // predict address
        address predicted = res.market.predictOrderAddress(params, salt);

        // create order with salt
        ITermMaxOrder order = res.market.createOrder(params, salt);

        // deployed clone should match prediction
        assertEq(address(order), predicted);

        // owner should be maker
        assertEq(Ownable(address(order)).owner(), params.maker);

        // order config persisted
        assertEq(order.orderConfig().maxXtReserve, orderConfig.maxXtReserve);

        vm.stopPrank();
    }

    // Predict twice yields same address
    function testPredictOrderAddressIsStable() public {
        OrderInitialParams memory params;
        params.maker = maker;
        params.orderConfig = orderConfig;
        uint256 salt = 123456;

        address a1 = res.market.predictOrderAddress(params, salt);
        address a2 = res.market.predictOrderAddress(params, salt);
        assertEq(a1, a2);
    }
}
