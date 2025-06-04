// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Constants} from "contracts/v1/lib/Constants.sol";
import {ITermMaxMarket, TermMaxMarket, MarketEvents, MarketErrors} from "contracts/v1/TermMaxMarket.sol";
import {MockFlashLoanReceiver} from "contracts/v1/test/MockFlashLoanReceiver.sol";
import {MockFlashRepayer} from "contracts/v1/test/MockFlashRepayer.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {
    IGearingToken,
    AbstractGearingToken,
    GearingTokenErrors,
    GearingTokenEvents
} from "contracts/v1/tokens/AbstractGearingToken.sol";
import {IMintableERC20} from "contracts/v1/tokens/MintableERC20.sol";
import {ITermMaxFactory, TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/v1/oracle/OracleAggregator.sol";
import "contracts/v1/storage/TermMaxStorage.sol";

contract GtTest is Test {
    using JSONLoader for *;
    using SafeCast for uint256;
    using SafeCast for int256;

    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    address maker = vm.randomAddress();
    string testdata;

    MockFlashLoanReceiver flashLoanReceiver;

    MockFlashRepayer flashRepayer;

    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");
        orderConfig.maxXtReserve = type(uint128).max;
        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order =
            res.market.createOrder(maker, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts);

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        uint256 amount = 15000e8;
        res.debt.mint(deployer, amount);
        res.debt.approve(address(res.market), amount);
        res.market.mint(deployer, amount);
        res.ft.transfer(address(res.order), amount);
        res.xt.transfer(address(res.order), amount);

        flashLoanReceiver = new MockFlashLoanReceiver(res.market);
        flashRepayer = new MockFlashRepayer(res.gt);

        vm.stopPrank();
    }

    function testMintGtByIssueFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);

        vm.startPrank(sender);

        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);

        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        uint256 issueFee = (debtAmt * res.market.mintGtFeeRatio()) / Constants.DECIMAL_BASE;
        vm.expectEmit();
        emit MarketEvents.IssueFt(
            sender, sender, 1, debtAmt, uint128(debtAmt - issueFee), uint128(issueFee), collateralData
        );

        (uint256 gtId, uint128 ftOutAmt) = res.market.issueFt(sender, debtAmt, collateralData);

        assert(ftOutAmt == (debtAmt - issueFee));
        assert(gtId == 1);

        state.collateralReserve += collateralAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.ft.balanceOf(marketConfig.treasurer) == issueFee);
        assert(res.ft.balanceOf(sender) == ftOutAmt);

        (address owner, uint128 d, bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt == abi.decode(cd, (uint256)));
        (, uint128 ltv,) = res.gt.getLiquidationInfo(gtId);
        assert(LoanUtils.calcLtv(res, debtAmt, collateralAmt) == ltv);

        vm.stopPrank();
    }

    function testMintGtByLeverage() public {
        vm.startPrank(sender);
        uint256 collateralAmt = 1e18;
        bytes memory callbackData = abi.encode(sender, collateralAmt);
        res.collateral.mint(address(flashLoanReceiver), collateralAmt);

        uint128 xtAmt = 90e8;
        uint256 debtAmt = xtAmt * Constants.DECIMAL_BASE / (Constants.DECIMAL_BASE - res.market.mintGtFeeRatio());

        uint128 debtAmtInForBuyXt = 5e8;
        uint128 minXTOut = 0e8;
        res.debt.mint(sender, debtAmtInForBuyXt);
        res.debt.approve(address(res.order), debtAmtInForBuyXt);
        res.order.swapExactTokenToToken(
            res.debt, res.xt, sender, debtAmtInForBuyXt, minXTOut, block.timestamp + 1 hours
        );
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);
        uint256 xtBefore = res.xt.balanceOf(address(sender));

        res.xt.approve(address(flashLoanReceiver), xtAmt);

        vm.expectEmit();
        emit MarketEvents.LeverageByXt(
            address(flashLoanReceiver),
            sender,
            1,
            uint128(debtAmt),
            xtAmt,
            uint128(debtAmt - xtAmt),
            abi.encode(collateralAmt)
        );
        uint256 gtId = flashLoanReceiver.leverageByXt(xtAmt, callbackData);

        assert(gtId == 1);
        state.collateralReserve += collateralAmt;
        state.debtReserve -= xtAmt;
        StateChecker.checkMarketState(res, state);

        uint256 xtAfter = res.xt.balanceOf(address(sender));
        assert(xtBefore - xtAfter == xtAmt);

        (address owner, uint128 d, bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt == abi.decode(cd, (uint256)));

        vm.stopPrank();
    }

    function testMintGtWhenOracleOutdated() public {
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);

        vm.prank(deployer);
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 3600)
        );
        res.oracle.acceptPendingOracle(address(res.collateral));
        vm.warp(block.timestamp + 3600);

        vm.startPrank(sender);
        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);

        vm.expectRevert(abi.encodeWithSelector(IOracle.OracleIsNotWorking.selector, address(res.collateral)));
        res.market.issueFt(sender, debtAmt, collateralData);

        vm.stopPrank();

        vm.startPrank(deployer);
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 365 days)
        );
        res.oracle.acceptPendingOracle(address(res.collateral));
        vm.stopPrank();

        vm.startPrank(sender);
        res.collateral.approve(address(res.gt), collateralAmt);
        res.market.issueFt(sender, debtAmt, collateralData);

        vm.stopPrank();
    }

    function testRevertByGtIsNotHealthyWhenIssueFt() public {
        // debt 1790 USD collaretal 2000USD ltv 0.891
        uint128 debtAmt = 1790e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);

        vm.startPrank(sender);

        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                GearingTokenErrors.GtIsNotHealthy.selector, 0, sender, LoanUtils.calcLtv(res, debtAmt, collateralAmt)
            )
        );
        res.market.issueFt(sender, debtAmt, collateralData);

        vm.stopPrank();
    }

    function testRevertByGtIsNotHealthyWhenCollateralCloseZero() public {
        // debt 5 USD collaretal 2e-7 USD
        uint128 debtAmt = 5e8;
        uint256 collateralAmt = 1;
        res.collateral.mint(sender, collateralAmt);

        vm.startPrank(sender);

        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                GearingTokenErrors.GtIsNotHealthy.selector, 0, sender, LoanUtils.calcLtv(res, debtAmt, collateralAmt)
            )
        );
        res.market.issueFt(sender, debtAmt, collateralData);

        vm.stopPrank();
    }

    function testRevertByGtIsNotHealthyWhenLeverage() public {
        vm.startPrank(sender);
        uint256 collateralAmt = 0.001e18;
        bytes memory callbackData = abi.encode(sender, collateralAmt);
        res.collateral.mint(address(flashLoanReceiver), collateralAmt);

        uint128 xtAmt = 90e8;
        uint256 debtAmt = xtAmt * Constants.DECIMAL_BASE / (Constants.DECIMAL_BASE - res.market.mintGtFeeRatio());

        uint128 debtAmtInForBuyXt = 5e8;
        uint128 minXTOut = 0e8;
        res.debt.mint(sender, debtAmtInForBuyXt);
        res.debt.approve(address(res.order), debtAmtInForBuyXt);
        res.order.swapExactTokenToToken(
            res.debt, res.xt, sender, debtAmtInForBuyXt, minXTOut, block.timestamp + 1 hours
        );

        res.xt.approve(address(flashLoanReceiver), xtAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                GearingTokenErrors.GtIsNotHealthy.selector, 0, sender, LoanUtils.calcLtv(res, debtAmt, collateralAmt)
            )
        );
        flashLoanReceiver.leverageByXt(xtAmt, callbackData);

        vm.stopPrank();
    }

    function testReapyByDebtToken() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        res.debt.mint(sender, debtAmt);

        res.debt.approve(address(res.gt), debtAmt);
        uint256 collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint256 debtBalanceBefore = res.debt.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);
        bool byDebtToken = true;
        vm.expectEmit();
        emit GearingTokenEvents.Repay(gtId, debtAmt, byDebtToken);
        res.gt.repay(gtId, debtAmt, byDebtToken);

        uint256 collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint256 debtBalanceAfter = res.debt.balanceOf(sender);
        state.debtReserve += debtAmt;
        state.collateralReserve -= collateralAmt;
        StateChecker.checkMarketState(res, state);

        assert(collateralBalanceAfter - collateralBalanceBefore == collateralAmt);
        assert(debtBalanceAfter + debtAmt == debtBalanceBefore);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testReapyByFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        // get FT token
        uint128 debtAmtInForBuyFt = 100e8;
        uint128 minFTOut = 0e8;
        res.debt.mint(sender, debtAmtInForBuyFt);
        res.debt.approve(address(res.order), debtAmtInForBuyFt);
        res.order.swapExactTokenToToken(
            res.debt, res.ft, sender, debtAmtInForBuyFt, minFTOut, block.timestamp + 1 hours
        );

        uint256 collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint256 ftBalanceBefore = res.ft.balanceOf(sender);
        uint256 ftInMarketBefore = res.ft.balanceOf(address(res.market));
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        res.ft.approve(address(res.gt), debtAmt);

        bool byDebtToken = false;
        vm.expectEmit();
        emit GearingTokenEvents.Repay(gtId, debtAmt, byDebtToken);
        res.gt.repay(gtId, debtAmt, byDebtToken);

        uint256 collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint256 ftBalanceAfter = res.ft.balanceOf(sender);
        uint256 ftInMarketAfter = res.ft.balanceOf(address(res.market));
        state.collateralReserve -= collateralAmt;
        StateChecker.checkMarketState(res, state);
        assert(ftInMarketAfter - debtAmt == ftInMarketBefore);
        assert(collateralBalanceAfter - collateralBalanceBefore == collateralAmt);
        assert(ftBalanceAfter + debtAmt == ftBalanceBefore);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testPatriallyReapy() public {
        uint128 debtAmt = 100e8;
        uint128 repayAmt = 10e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        // Repay repayAmt
        address thirdPeople = vm.randomAddress();
        res.debt.mint(thirdPeople, debtAmt);
        // Repay repayAmt
        vm.startPrank(thirdPeople);
        res.debt.approve(address(res.gt), debtAmt);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        bool byDebtToken = true;
        vm.expectEmit();
        emit GearingTokenEvents.Repay(gtId, repayAmt, byDebtToken);
        res.gt.repay(gtId, repayAmt, byDebtToken);
        state.debtReserve += repayAmt;
        StateChecker.checkMarketState(res, state);
        assert(res.debt.balanceOf(thirdPeople) == debtAmt - repayAmt);
        assert(res.collateral.balanceOf(thirdPeople) == 0);

        (address owner, uint128 d, bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt - repayAmt);
        assert(collateralAmt == abi.decode(cd, (uint256)));

        // Repay all
        uint256 debtBalanceBefore = res.debt.balanceOf(sender);
        uint256 collateralBalanceBefore = res.collateral.balanceOf(sender);

        vm.expectEmit();
        emit GearingTokenEvents.Repay(gtId, debtAmt - repayAmt, byDebtToken);
        res.gt.repay(gtId, debtAmt - repayAmt, byDebtToken);

        state.debtReserve += (debtAmt - repayAmt);
        state.collateralReserve -= collateralAmt;
        uint256 collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint256 debtBalanceAfter = res.debt.balanceOf(sender);
        StateChecker.checkMarketState(res, state);

        assert(collateralBalanceAfter - collateralBalanceBefore == collateralAmt);
        assert(debtBalanceAfter == debtBalanceBefore);
        assert(res.debt.balanceOf(thirdPeople) == 0);
        assert(res.collateral.balanceOf(thirdPeople) == 0);

        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testFlashRepay() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        res.debt.mint(address(flashRepayer), debtAmt);
        res.gt.approve(address(flashRepayer), gtId);

        uint256 collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint256 debtBalanceBefore = res.debt.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);
        bool byDebtToken = true;
        vm.expectEmit();
        emit GearingTokenEvents.Repay(gtId, debtAmt, byDebtToken);
        flashRepayer.flashRepay(gtId, byDebtToken);

        uint256 collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint256 debtBalanceAfter = res.debt.balanceOf(sender);
        state.debtReserve += debtAmt;
        state.collateralReserve -= collateralAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.collateral.balanceOf(address(flashRepayer)) == collateralAmt);
        assert(res.debt.balanceOf(address(flashRepayer)) == 0);
        assert(collateralBalanceAfter == collateralBalanceBefore);
        assert(debtBalanceAfter == debtBalanceBefore);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    // function testFlashRepayThroughFt() public {
    //     uint128 debtAmt = 100e8;
    //     uint256 collateralAmt = 1e18;

    //     vm.startPrank(sender);

    //     (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
    //     deal(address(res.ft), address(flashRepayer), debtAmt);

    //     res.gt.approve(address(flashRepayer), gtId);

    //     uint collateralBalanceBefore = res.collateral.balanceOf(sender);
    //     uint ftBalanceBefore = res.ft.balanceOf(sender);
    //     StateChecker.MarketState memory state = StateChecker.getMarketState(res);
    //     bool byDebtToken = false;
    //     vm.expectEmit();
    //     emit GearingTokenEvents.Repay(gtId, debtAmt, byDebtToken);
    //     flashRepayer.flashRepay(gtId, byDebtToken);

    //     uint collateralBalanceAfter = res.collateral.balanceOf(sender);
    //     uint ftBalanceAfter = res.ft.balanceOf(sender);
    //     state.ftReserve += debtAmt;
    //     state.collateralReserve -= collateralAmt;
    //     StateChecker.checkMarketState(res, state);

    //     assert(res.collateral.balanceOf(address(flashRepayer)) == collateralAmt);
    //     assert(res.debt.balanceOf(address(flashRepayer)) == 0);
    //     assert(collateralBalanceAfter == collateralBalanceBefore);
    //     assert(ftBalanceAfter == ftBalanceBefore);
    //     vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
    //     res.gt.loanInfo(gtId);

    //     vm.stopPrank();
    // }

    function testRevertByGtIsExpiredWhenRepay() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.warp(marketConfig.maturity);
        res.debt.mint(sender, debtAmt);

        res.debt.approve(address(res.gt), debtAmt);

        vm.expectRevert(abi.encodeWithSelector(GearingTokenErrors.GtIsExpired.selector, gtId));
        res.gt.repay(gtId, debtAmt, true);

        vm.stopPrank();
    }

    function testRevertByGtIsExpiredWhenFlashRepay() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.warp(marketConfig.maturity);
        res.debt.mint(address(flashRepayer), debtAmt);
        res.gt.approve(address(flashRepayer), gtId);

        vm.expectRevert(abi.encodeWithSelector(GearingTokenErrors.GtIsExpired.selector, gtId));
        flashRepayer.flashRepay(gtId, true);
    }

    function testMerge() public {
        uint40[3] memory debts = [100e8, 30e8, 5e8];
        uint64[3] memory collaterals = [1e18, 0.5e18, 0.05e18];

        vm.startPrank(sender);

        uint256[] memory ids = new uint256[](3);
        for (uint256 i = 0; i < ids.length; ++i) {
            (ids[i],) = LoanUtils.fastMintGt(res, sender, debts[i], collaterals[i]);
        }
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        uint256 newId = 4;
        emit GearingTokenEvents.MergeGts(sender, newId, ids);
        newId = res.gt.merge(ids);
        StateChecker.checkMarketState(res, state);

        (address owner, uint128 d, bytes memory cd) = res.gt.loanInfo(newId);
        assert(owner == sender);
        assert(d == debts[0] + debts[1] + debts[2]);
        assert(collaterals[0] + collaterals[1] + collaterals[2] == abi.decode(cd, (uint256)));
        for (uint256 i = 0; i < ids.length; i++) {
            vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), ids[i]));
            res.gt.loanInfo(ids[i]);
        }

        vm.stopPrank();
    }

    function testRevertByCanNotMergeLoanWithDiffOwnerWhenMerge() public {
        uint40[3] memory debts = [100e8, 30e8, 5e8];
        uint64[3] memory collaterals = [1e18, 0.5e18, 0.005e18];

        vm.startPrank(sender);

        uint256[] memory ids = new uint256[](3);
        for (uint256 i = 0; i < ids.length; ++i) {
            (ids[i],) = LoanUtils.fastMintGt(res, sender, debts[i], collaterals[i]);
        }
        vm.stopPrank();
        vm.prank(vm.randomAddress());
        vm.expectRevert(
            abi.encodeWithSelector(GearingTokenErrors.CanNotMergeLoanWithDiffOwner.selector, ids[0], sender)
        );
        res.gt.merge(ids);
    }

    function testAddCollateral() public {
        uint128 debtAmt = 1700e8;
        uint256 collateralAmt = 1e18;
        uint256 addedCollateral = 0.1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        // Add collateral by third address
        address thirdPeople = vm.randomAddress();
        res.collateral.mint(thirdPeople, addedCollateral);
        vm.startPrank(thirdPeople);

        res.collateral.approve(address(res.gt), addedCollateral);

        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        emit GearingTokenEvents.AddCollateral(gtId, abi.encode(collateralAmt + addedCollateral));
        res.gt.addCollateral(gtId, abi.encode(addedCollateral));

        state.collateralReserve += addedCollateral;
        StateChecker.checkMarketState(res, state);
        assert(res.debt.balanceOf(thirdPeople) == 0);
        assert(res.collateral.balanceOf(thirdPeople) == 0);

        (address owner, uint128 d, bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt + addedCollateral == abi.decode(cd, (uint256)));

        // Add collateral by self
        vm.startPrank(sender);

        res.collateral.mint(sender, addedCollateral);
        res.collateral.approve(address(res.gt), addedCollateral);

        res.gt.addCollateral(gtId, abi.encode(addedCollateral));
        vm.stopPrank();
    }

    function testRevertByGtIsExpiredWhenAddCollateral() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        uint256 addedCollateral = 0.1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        vm.stopPrank();

        address thirdPeople = vm.randomAddress();
        vm.warp(marketConfig.maturity);
        res.collateral.mint(thirdPeople, addedCollateral);

        vm.startPrank(thirdPeople);
        res.collateral.approve(address(res.gt), addedCollateral);

        vm.expectRevert(abi.encodeWithSelector(GearingTokenErrors.GtIsExpired.selector, gtId));

        res.gt.addCollateral(gtId, abi.encode(addedCollateral));
        vm.stopPrank();
    }

    function testRemoveCollateral() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        uint256 removedCollateral = 0.1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        StateChecker.MarketState memory state = StateChecker.getMarketState(res);
        uint256 collateralBlanceBefore = res.collateral.balanceOf(sender);

        vm.expectEmit();
        emit GearingTokenEvents.RemoveCollateral(gtId, abi.encode(collateralAmt - removedCollateral));
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));

        state.collateralReserve -= removedCollateral;
        StateChecker.checkMarketState(res, state);

        uint256 collateralBlanceAfter = res.collateral.balanceOf(sender);

        assert(collateralBlanceAfter - collateralBlanceBefore == removedCollateral);

        (address owner, uint128 d, bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt - removedCollateral == abi.decode(cd, (uint256)));

        vm.stopPrank();
    }

    function testRemoveCollateralWhenOracleOutdated() public {
        // debt 100 USD collaretal 2200USD
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1.1e18;
        uint256 removedCollateral = 0.1e18;
        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();

        vm.prank(deployer);
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 3600)
        );
        vm.prank(deployer);
        res.oracle.acceptPendingOracle(address(res.collateral));
        vm.warp(block.timestamp + 3600);

        vm.expectRevert(abi.encodeWithSelector(IOracle.OracleIsNotWorking.selector, address(res.collateral)));
        vm.prank(sender);
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));

        vm.prank(deployer);
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 365 days)
        );
        vm.prank(deployer);
        res.oracle.acceptPendingOracle(address(res.collateral));

        vm.prank(sender);
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));
    }

    function testRevertByGtIsNotHealthyWhenRemoveCollateral() public {
        // debt 1780 USD collaretal 2200USD
        uint128 debtAmt = 1790e8;
        uint256 collateralAmt = 1.1e18;
        uint256 removedCollateral = 0.1e18;
        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                GearingTokenErrors.GtIsNotHealthy.selector,
                gtId,
                sender,
                LoanUtils.calcLtv(res, debtAmt, collateralAmt - removedCollateral)
            )
        );
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));

        vm.stopPrank();
    }

    function testRevertByCallerIsNotTheOwnerWhenRemoveCollateral() public {
        // debt 1780 USD collaretal 2200USD
        uint128 debtAmt = 1780e8;
        uint256 collateralAmt = 1.1e18;
        uint256 removedCollateral = 0.1e18;
        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();

        address thirdPeople = vm.randomAddress();
        vm.expectRevert(abi.encodeWithSelector(GearingTokenErrors.CallerIsNotTheOwner.selector, gtId));
        vm.prank(thirdPeople);
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));
    }

    function testRevertByGtIsExpiredWhenRemoveCollateral() public {
        // debt 200 USD collaretal 2200USD
        uint128 debtAmt = 200e8;
        uint256 collateralAmt = 1.1e18;
        uint256 removedCollateral = 0.1e18;
        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        vm.stopPrank();

        vm.warp(marketConfig.maturity);

        vm.expectRevert(abi.encodeWithSelector(GearingTokenErrors.GtIsExpired.selector, gtId));
        vm.prank(sender);
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));
    }

    // Case 1: removed collateral can not cover repayAmt + rewardToLiquidator
    function testLiquidateCase1() public {
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, debtAmt);
        res.debt.approve(address(res.gt), debtAmt);

        uint256 senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        uint256 cToLiquidator = collateralAmt;
        uint256 cToTreasurer = 0;
        uint256 remainningC = 0;
        emit GearingTokenEvents.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            true,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt, true);
        state.collateralReserve -= collateralAmt;
        state.debtReserve += debtAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer);
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == remainningC + senderCBalanceBefore);
        vm.stopPrank();
    }

    // Case 2: removed collateral can cover repayAmt + rewardToLiquidator but not rewardToProtocol
    function testLiquidateCase2() public {
        uint128 debtAmt = 950e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, debtAmt);
        res.debt.approve(address(res.gt), debtAmt);

        uint256 senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        // uint cToLiquidator = 0.9975e18;
        // uint cToTreasurer = 0.0025e18;
        // uint remainningC = 0;
        (uint256 cToLiquidator, uint256 cToTreasurer, uint256 remainningC) =
            LoanUtils.calcLiquidationResult(res, debtAmt, collateralAmt, debtAmt);
        emit GearingTokenEvents.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            true,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt, true);
        state.collateralReserve -= collateralAmt;
        state.debtReserve += debtAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer);
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == remainningC + senderCBalanceBefore);
        vm.stopPrank();
    }

    // Case 3: removed collateral equal repayAmt + rewardToLiquidator + rewardToProtocol
    function testLiquidateCase3() public {
        uint128 debtAmt = 900e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, debtAmt);
        res.debt.approve(address(res.gt), debtAmt);

        uint256 senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        // uint cToLiquidator = 0.945e18;
        // uint cToTreasurer = 0.045e18;
        // uint remainningC = 0.01e18;
        (uint256 cToLiquidator, uint256 cToTreasurer, uint256 remainningC) =
            LoanUtils.calcLiquidationResult(res, debtAmt, collateralAmt, debtAmt);
        emit GearingTokenEvents.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            true,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt, true);
        state.collateralReserve -= collateralAmt;
        state.debtReserve += debtAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer);
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == remainningC + senderCBalanceBefore);
        vm.stopPrank();
    }

    function testLiquidateByFt() public {
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, debtAmt);
        res.debt.approve(address(res.market), debtAmt);
        res.market.mint(liquidator, debtAmt);
        res.ft.approve(address(res.gt), debtAmt);

        uint256 senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        uint256 cToLiquidator = collateralAmt;
        uint256 cToTreasurer = 0;
        uint256 remainningC = 0;
        emit GearingTokenEvents.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            false,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt, false);
        state.collateralReserve -= collateralAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.ft.balanceOf(address(res.market)) == debtAmt);
        assert(res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer);
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == remainningC + senderCBalanceBefore);
        vm.stopPrank();
    }

    function testRemovedCollateralLessThanRepayAmt() public {
        uint128 debtAmt = 900e8;
        uint256 collateralAmt = 0.93e18;
        uint128 repayAmt = 300e8;
        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, repayAmt);
        res.debt.approve(address(res.gt), repayAmt);

        uint256 senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        // uint cToLiquidator = 0.31e18;
        // uint cToTreasurer = 0;
        // uint remainningC = 0.62e18;
        (uint256 cToLiquidator, uint256 cToTreasurer, uint256 remainningC) =
            LoanUtils.calcLiquidationResult(res, debtAmt, collateralAmt, repayAmt);
        emit GearingTokenEvents.Liquidate(
            gtId,
            liquidator,
            repayAmt,
            true,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, repayAmt, true);
        state.collateralReserve -= (cToLiquidator + cToTreasurer);
        state.debtReserve += repayAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer);
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == senderCBalanceBefore);
        vm.stopPrank();
    }

    function testHalfLiquidate() public {
        uint128 debtAmt = 9000e8;
        uint256 collateralAmt = 10e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();
        (bool isLiquidable,, uint128 maxRepayAmt) = res.gt.getLiquidationInfo(gtId);
        assert(isLiquidable);
        assert(maxRepayAmt == debtAmt / 2);
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, maxRepayAmt);
        res.debt.approve(address(res.gt), maxRepayAmt);

        uint256 senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        // uint cToLiquidator = 4.725e18;
        // uint cToTreasurer = 0.225e18;
        // uint remainningC = 5.05e18;
        (uint256 cToLiquidator, uint256 cToTreasurer, uint256 remainningC) =
            LoanUtils.calcLiquidationResult(res, debtAmt, collateralAmt, maxRepayAmt);
        emit GearingTokenEvents.Liquidate(
            gtId,
            liquidator,
            maxRepayAmt,
            true,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, maxRepayAmt, true);
        state.collateralReserve -= (cToLiquidator + cToTreasurer);
        state.debtReserve += maxRepayAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer);
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == senderCBalanceBefore);
        vm.stopPrank();

        (address owner, uint128 newDebtAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(newDebtAmt == debtAmt - maxRepayAmt);

        assert(remainningC == abi.decode(collateralData, (uint256)));
        uint128 ltv;
        (isLiquidable, ltv, maxRepayAmt) = res.gt.getLiquidationInfo(gtId);
        assert(ltv < liquidationLtv);
        assert(!isLiquidable);
        assert(maxRepayAmt == 0);
    }

    function testLiquidateInWindowTime(uint16 exceedTime) public {
        vm.assume(exceedTime < Constants.LIQUIDATION_WINDOW);
        uint256 liquidateTime = marketConfig.maturity + exceedTime;
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();

        vm.warp(liquidateTime);
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, debtAmt);
        res.debt.approve(address(res.gt), debtAmt);

        uint256 senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        uint256 cToLiquidator = collateralAmt;
        uint256 cToTreasurer = 0;
        uint256 remainningC = 0;
        emit GearingTokenEvents.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            true,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt, true);
        state.collateralReserve -= collateralAmt;
        state.debtReserve += debtAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer);
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == remainningC + senderCBalanceBefore);
        vm.stopPrank();
    }

    function testLiquidatable() public {
        uint128 debtAmt = 10000e8;
        uint256 collateralAmt = 10e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();

        vm.warp(marketConfig.maturity - 1);
        (bool isLiquidable,, uint128 maxRepayAmt) = res.gt.getLiquidationInfo(gtId);
        assert(isLiquidable);
        assert(maxRepayAmt == debtAmt / 2);

        vm.warp(marketConfig.maturity);
        (isLiquidable,, maxRepayAmt) = res.gt.getLiquidationInfo(gtId);
        assert(isLiquidable);
        assert(maxRepayAmt == debtAmt);

        vm.warp(marketConfig.maturity + Constants.LIQUIDATION_WINDOW);
        (isLiquidable,, maxRepayAmt) = res.gt.getLiquidationInfo(gtId);
        assert(!isLiquidable);
        assert(maxRepayAmt == 0);
    }

    function testLiquidateWithDecimalsExceed8() public {
        uint128 debtAmt = 1e8;
        uint256 collateralAmt = 1.01e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        MockPriceFeed.RoundData memory data = JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth");
        data.answer = 1e18; // eth price 1e8
        res.collateralOracle.updateRoundData(data);
        data.answer = 1e8; // dai price 1e18
        res.debtOracle.updateRoundData(data);
        vm.stopPrank();

        vm.warp(marketConfig.maturity + 1);

        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, debtAmt);
        res.debt.approve(address(res.gt), debtAmt);

        uint256 senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(res);

        vm.expectEmit();
        (uint256 cToLiquidator, uint256 cToTreasurer, uint256 remainningC) =
            LoanUtils.calcLiquidationResult(res, debtAmt, collateralAmt, debtAmt);
        emit GearingTokenEvents.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            true,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt, true);
        state.collateralReserve -= collateralAmt;
        state.debtReserve += debtAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer);
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == remainningC + senderCBalanceBefore);
        vm.stopPrank();
    }

    function testLiquidateWhenOracleOutdated() public {
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        MockPriceFeed.RoundData memory peth = JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth");
        MockPriceFeed.RoundData memory pdai = JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai");
        peth.updatedAt = block.timestamp - 1;
        pdai.updatedAt = block.timestamp - 1;
        res.collateralOracle.updateRoundData(peth);
        res.debtOracle.updateRoundData(pdai);

        vm.stopPrank();

        vm.prank(deployer);
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 3600)
        );
        res.oracle.acceptPendingOracle(address(res.collateral));

        vm.warp(block.timestamp + 3600);
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, debtAmt);
        res.debt.approve(address(res.gt), debtAmt);

        vm.expectRevert(abi.encodeWithSelector(IOracle.OracleIsNotWorking.selector, address(res.collateral)));
        res.gt.liquidate(gtId, debtAmt, true);

        vm.stopPrank();
        vm.warp(block.timestamp - 1);
        vm.prank(liquidator);
        res.gt.liquidate(gtId, debtAmt, true);
    }

    function testRevertByGtIsSafeWhenLiquidate() public {
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();

        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, debtAmt);
        res.debt.approve(address(res.gt), debtAmt);

        vm.expectRevert(abi.encodeWithSelector(GearingTokenErrors.GtIsSafe.selector, gtId));
        res.gt.liquidate(gtId, debtAmt, true);

        vm.stopPrank();
    }

    function testRevertByCanNotLiquidationAfterFinalDeadline() public {
        uint256 liquidateTime = marketConfig.maturity + Constants.LIQUIDATION_WINDOW;
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();

        vm.warp(liquidateTime);
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, debtAmt);
        res.debt.approve(address(res.gt), debtAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                GearingTokenErrors.CanNotLiquidationAfterFinalDeadline.selector,
                gtId,
                marketConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        res.gt.liquidate(gtId, debtAmt, true);
    }

    function testRevertByRepayAmtExceedsMaxRepayAmt() public {
        uint128 debtAmt = 9000e8;
        uint256 collateralAmt = 10e18;

        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();
        (bool isLiquidable,, uint128 maxRepayAmt) = res.gt.getLiquidationInfo(gtId);
        assert(isLiquidable);
        assert(maxRepayAmt == debtAmt / 2);
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        uint128 repayAmt = maxRepayAmt + 1;
        res.debt.mint(liquidator, repayAmt);
        res.debt.approve(address(res.gt), repayAmt);

        vm.expectRevert(
            abi.encodeWithSelector(GearingTokenErrors.RepayAmtExceedsMaxRepayAmt.selector, gtId, repayAmt, maxRepayAmt)
        );
        res.gt.liquidate(gtId, repayAmt, true);

        vm.stopPrank();
    }

    function testNoRevertByLtvIncreasedAfterLiquidation(uint128 repayAmt) public {
        uint128 debtAmt = 900e8;
        vm.assume(repayAmt >= 5e8 && repayAmt <= debtAmt - 5e8);
        uint256 collateralAmt = 0.6e18;
        vm.startPrank(sender);

        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_1000_DAI_1.dai"));
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.debt.mint(liquidator, repayAmt);
        res.debt.approve(address(res.gt), repayAmt);

        StateChecker.MarketState memory state = StateChecker.getMarketState(res);
        (uint256 cToLiquidator, uint256 cToTreasurer, uint256 remainningC) =
            LoanUtils.calcLiquidationResult(res, debtAmt, collateralAmt, repayAmt);
        emit GearingTokenEvents.Liquidate(
            gtId,
            liquidator,
            repayAmt,
            true,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );
        res.gt.liquidate(gtId, repayAmt, true);
        if (repayAmt < debtAmt) {
            state.collateralReserve -= (cToLiquidator + cToTreasurer);
        } else {
            state.collateralReserve -= collateralAmt;
        }
        state.debtReserve += repayAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer);
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);

        vm.stopPrank();
    }

    function testFuzzMintGt(uint128 debtAmt, uint128 debtAmt2) public {
        uint256 collateralAmt = 1e18;
        vm.assume(debtAmt <= 1000e8);
        vm.assume(debtAmt2 <= 600e8);
        vm.startPrank(sender);
        res.collateral.mint(sender, collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        (uint256 gtId,) = res.market.issueFt(sender, debtAmt, collateralData);

        res.market.issueFtByExistedGt(sender, debtAmt2, gtId);
        vm.stopPrank();
    }

    function testLiquidateZeroDebt() public {
        uint256 collateralAmt = 1e18;
        uint128 debtAmt = 0;
        vm.startPrank(sender);
        res.collateral.mint(sender, collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        (uint256 gtId,) = res.market.issueFt(sender, debtAmt, collateralData);
        vm.stopPrank();

        address liquidator = vm.randomAddress();
        uint128 repayAmt = 0;
        vm.startPrank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(GearingTokenErrors.GtIsSafe.selector, gtId));
        res.gt.liquidate(gtId, repayAmt, true);

        vm.warp(marketConfig.maturity);
        res.gt.liquidate(gtId, repayAmt, true);

        assertEq(res.collateral.balanceOf(liquidator), 0);
        assertEq(res.collateral.balanceOf(marketConfig.treasurer), 0);
        assertEq(res.debt.balanceOf(sender), debtAmt);
        vm.stopPrank();
    }

    function testRepayZeroDebt() public {
        uint256 collateralAmt = 1e18;
        uint128 debtAmt = 0;
        vm.startPrank(sender);
        res.collateral.mint(sender, collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        (uint256 gtId,) = res.market.issueFt(sender, debtAmt, collateralData);

        res.gt.repay(gtId, 0, true);
        assertEq(res.collateral.balanceOf(sender), collateralAmt);
        vm.stopPrank();
    }
}
