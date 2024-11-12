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
import {ITermMaxMarket, TermMaxMarket, Constants, IERC20} from "../contracts/core/TermMaxMarket.sol";
import {MockFlashLoanReceiver} from "../contracts/test/MockFlashLoanReceiver.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {AbstractGearingToken} from "../contracts/core/tokens/AbstractGearingToken.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../contracts/core/factory/TermMaxFactory.sol";
import "../contracts/core/storage/TermMaxStorage.sol";

contract GtTest is Test {
    using JSONLoader for *;
    using SafeCast for uint256;
    using SafeCast for int256;
    DeployUtils.Res res;

    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    MockFlashLoanReceiver flashLoanReceiver;

    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/testdata.json")
        );

        marketConfig = JSONLoader.getMarketConfigFromJson(
            treasurer,
            testdata,
            ".marketConfig"
        );
        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );

        flashLoanReceiver = new MockFlashLoanReceiver(res.market);

        vm.warp(
            vm.parseUint(
                vm.parseJsonString(testdata, ".marketConfig.currentTime")
            )
        );

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_DAI_1.dai"
            )
        );

        uint amount = 10000e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(amount);

        vm.stopPrank();
    }

    function testMintGtByIssueFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);

        vm.startPrank(sender);

        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        uint issueFee = (debtAmt * marketConfig.issueFtFeeRatio) /
            Constants.DECIMAL_BASE;
        vm.expectEmit();
        emit ITermMaxMarket.IssueFt(
            sender,
            1,
            debtAmt,
            uint128(debtAmt - issueFee),
            uint128(issueFee),
            collateralData
        );

        (uint256 gtId, uint128 ftOutAmt) = res.market.issueFt(
            debtAmt,
            collateralData
        );

        assert(ftOutAmt == (debtAmt - issueFee));
        assert(gtId == 1);

        state.collateralReserve += collateralAmt;
        StateChecker.checkMarketState(res, state);

        assert(res.ft.balanceOf(marketConfig.treasurer) == issueFee);
        assert(res.ft.balanceOf(sender) == ftOutAmt);

        (address owner, uint128 d, uint128 ltv, bytes memory cd) = res
            .gt
            .loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt == abi.decode(cd, (uint256)));

        assert(LoanUtils.calcLtv(res, debtAmt, collateralAmt) == ltv);

        vm.stopPrank();
    }

    function testMintGtByLeverage() public {
        uint collateralAmt = 1e18;
        bytes memory callbackData = abi.encode(sender, collateralAmt);
        res.collateral.mint(address(flashLoanReceiver), collateralAmt);

        uint128 xtAmt = 90e8;
        uint debtAmt = (xtAmt *
            marketConfig.initialLtv +
            Constants.DECIMAL_BASE -
            1) / Constants.DECIMAL_BASE;
        res.underlying.mint(address(sender), xtAmt);
        vm.startPrank(sender);
        res.underlying.approve(address(res.market), xtAmt);

        // get XT token
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            xtAmt
        );
        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        res.market.withdrawLp(lpFtOutAmt, lpXtOutAmt);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        uint xtBefore = res.xt.balanceOf(address(sender));

        res.xt.approve(address(flashLoanReceiver), xtAmt);

        vm.expectEmit();
        emit ITermMaxMarket.MintGt(
            address(flashLoanReceiver),
            sender,
            1,
            uint128(debtAmt),
            abi.encode(collateralAmt)
        );
        uint256 gtId = flashLoanReceiver.leverageByXt(xtAmt, callbackData);

        assert(gtId == 1);
        state.collateralReserve += collateralAmt;
        state.underlyingReserve -= debtAmt;
        StateChecker.checkMarketState(res, state);

        uint xtAfter = res.xt.balanceOf(address(sender));
        assert(xtBefore - xtAfter == xtAmt);

        (address owner, uint128 d, uint128 ltv, bytes memory cd) = res
            .gt
            .loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt == abi.decode(cd, (uint256)));
        assert(LoanUtils.calcLtv(res, debtAmt, collateralAmt) == ltv);

        vm.stopPrank();
    }

    function testRevertByGtIsNotHealthyWhenIssueFt() public {
        // debt 1780 USD collaretal 2000USD ltv 0.89
        uint128 debtAmt = 1780e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);

        vm.startPrank(sender);

        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.GtIsNotHealthy.selector,
                0,
                sender,
                LoanUtils.calcLtv(res, debtAmt, collateralAmt)
            )
        );
        res.market.issueFt(debtAmt, collateralData);

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
                IGearingToken.GtIsNotHealthy.selector,
                0,
                sender,
                LoanUtils.calcLtv(res, debtAmt, collateralAmt)
            )
        );
        res.market.issueFt(debtAmt, collateralData);

        vm.stopPrank();
    }

    function testRevertByDebtValueIsTooSmallWhenMintGt() public {
        // debt 4 USD collaretal 2000USD ltv 0.89
        uint128 debtAmt = 4e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);

        vm.startPrank(sender);

        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.DebtValueIsTooSmall.selector,
                debtAmt
            )
        );
        res.market.issueFt(debtAmt, collateralData);

        vm.stopPrank();
    }

    function testRevertByGtIsNotHealthyWhenLeverage() public {
        uint collateralAmt = 1e18;
        bytes memory callbackData = abi.encode(sender, collateralAmt);
        res.collateral.mint(address(flashLoanReceiver), collateralAmt);
        // debt 1848 USD collaretal 2000USD ltv 0.924
        uint128 xtAmt = 2100e8;
        uint debtAmt = (xtAmt *
            marketConfig.initialLtv +
            Constants.DECIMAL_BASE -
            1) / Constants.DECIMAL_BASE;
        res.underlying.mint(address(sender), xtAmt);
        vm.startPrank(sender);
        res.underlying.approve(address(res.market), xtAmt);

        // get XT token
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            xtAmt
        );
        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        res.market.withdrawLp(lpFtOutAmt, lpXtOutAmt);

        res.xt.approve(address(flashLoanReceiver), xtAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.GtIsNotHealthy.selector,
                0,
                sender,
                LoanUtils.calcLtv(res, debtAmt, collateralAmt)
            )
        );
        flashLoanReceiver.leverageByXt(xtAmt, callbackData);

        vm.stopPrank();
    }

    function testReapyByUnderlying() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        res.underlying.mint(sender, debtAmt);

        res.underlying.approve(address(res.gt), debtAmt);
        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        bool byUnderlying = true;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, debtAmt, byUnderlying);
        res.gt.repay(gtId, debtAmt, byUnderlying);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);
        state.underlyingReserve += debtAmt;
        state.collateralReserve -= collateralAmt;
        StateChecker.checkMarketState(res, state);

        assert(
            collateralBalanceAfter - collateralBalanceBefore == collateralAmt
        );
        assert(underlyingBalanceAfter + debtAmt == underlyingBalanceBefore);
        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                gtId
            )
        );
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testReapyByFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        // get FT token
        res.underlying.mint(sender, debtAmt);
        res.underlying.approve(address(res.market), debtAmt);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            debtAmt
        );
        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        res.market.withdrawLp(lpFtOutAmt, lpXtOutAmt);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint ftBalanceBefore = res.ft.balanceOf(sender);
        uint ftInGtBefore = res.ft.balanceOf(address(res.gt));
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        res.ft.approve(address(res.gt), debtAmt);

        bool byUnderlying = false;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, debtAmt, byUnderlying);
        res.gt.repay(gtId, debtAmt, byUnderlying);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint ftBalanceAfter = res.ft.balanceOf(sender);
        uint ftInGtAfter = res.ft.balanceOf(address(res.gt));
        state.collateralReserve -= collateralAmt;
        StateChecker.checkMarketState(res, state);
        assert(ftInGtAfter - debtAmt == ftInGtBefore);
        assert(
            collateralBalanceAfter - collateralBalanceBefore == collateralAmt
        );
        assert(ftBalanceAfter + debtAmt == ftBalanceBefore);
        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                gtId
            )
        );
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testPatriallyReapy() public {
        uint128 debtAmt = 100e8;
        uint128 repayAmt = 10e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();

        address thirdPeople = vm.randomAddress();
        res.underlying.mint(thirdPeople, debtAmt);
        // Repay repayAmt
        vm.startPrank(thirdPeople);
        res.underlying.approve(address(res.gt), debtAmt);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        bool byUnderlying = true;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, repayAmt, byUnderlying);
        res.gt.repay(gtId, repayAmt, byUnderlying);
        state.underlyingReserve += repayAmt;
        StateChecker.checkMarketState(res, state);
        assert(res.underlying.balanceOf(thirdPeople) == debtAmt - repayAmt);
        assert(res.collateral.balanceOf(thirdPeople) == 0);

        (address owner, uint128 d, , bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt - repayAmt);
        assert(collateralAmt == abi.decode(cd, (uint256)));

        // Repay all
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);
        uint collateralBalanceBefore = res.collateral.balanceOf(sender);

        vm.expectEmit();
        emit IGearingToken.Repay(gtId, debtAmt - repayAmt, byUnderlying);
        res.gt.repay(gtId, debtAmt - repayAmt, byUnderlying);

        state.underlyingReserve += (debtAmt - repayAmt);
        state.collateralReserve -= collateralAmt;
        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);
        StateChecker.checkMarketState(res, state);

        assert(
            collateralBalanceAfter - collateralBalanceBefore == collateralAmt
        );
        assert(underlyingBalanceAfter == underlyingBalanceBefore);
        assert(res.underlying.balanceOf(thirdPeople) == 0);
        assert(res.collateral.balanceOf(thirdPeople) == 0);

        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                gtId
            )
        );
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testRevertByGtIsExpiredWhenRepay() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.warp(marketConfig.maturity);
        res.underlying.mint(sender, debtAmt);

        res.underlying.approve(address(res.gt), debtAmt);

        vm.expectRevert(
            abi.encodeWithSelector(IGearingToken.GtIsExpired.selector, gtId)
        );
        res.gt.repay(gtId, debtAmt, true);

        vm.stopPrank();
    }

    function testMerge() public {
        uint40[3] memory debts = [100e8, 30e8, 5e8];
        uint64[3] memory collaterals = [1e18, 0.5e18, 0.05e18];

        vm.startPrank(sender);

        uint[] memory ids = new uint[](3);
        for (uint i = 0; i < ids.length; ++i) {
            (ids[i], ) = LoanUtils.fastMintGt(
                res,
                sender,
                debts[i],
                collaterals[i]
            );
        }
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        uint newId = 4;
        emit IGearingToken.MergeGts(sender, newId, ids);
        newId = res.gt.merge(ids);
        StateChecker.checkMarketState(res, state);

        (address owner, uint128 d, , bytes memory cd) = res.gt.loanInfo(newId);
        assert(owner == sender);
        assert(d == debts[0] + debts[1] + debts[2]);
        assert(
            collaterals[0] + collaterals[1] + collaterals[2] ==
                abi.decode(cd, (uint256))
        );
        for (uint i = 0; i < ids.length; i++) {
            vm.expectRevert(
                abi.encodePacked(
                    bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                    ids[i]
                )
            );
            res.gt.loanInfo(ids[i]);
        }

        vm.stopPrank();
    }

    function testRevertByCanNotMergeLoanWithDiffOwnerWhenMerge() public {
        uint40[3] memory debts = [100e8, 30e8, 5e8];
        uint64[3] memory collaterals = [1e18, 0.5e18, 0.005e18];

        vm.startPrank(sender);

        uint[] memory ids = new uint[](3);
        for (uint i = 0; i < ids.length; ++i) {
            (ids[i], ) = LoanUtils.fastMintGt(
                res,
                sender,
                debts[i],
                collaterals[i]
            );
        }
        vm.stopPrank();
        vm.prank(vm.randomAddress());
        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.CanNotMergeLoanWithDiffOwner.selector,
                ids[0],
                sender
            )
        );
        res.gt.merge(ids);
    }

    function testAddCollateral() public {
        uint128 debtAmt = 1700e8;
        uint256 collateralAmt = 1e18;
        uint256 addedCollateral = 0.1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        // Add collateral by third address
        address thirdPeople = vm.randomAddress();
        res.collateral.mint(thirdPeople, addedCollateral);
        vm.startPrank(thirdPeople);

        res.collateral.approve(address(res.gt), addedCollateral);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        emit IGearingToken.AddCollateral(
            gtId,
            abi.encode(collateralAmt + addedCollateral)
        );
        res.gt.addCollateral(gtId, abi.encode(addedCollateral));

        state.collateralReserve += addedCollateral;
        StateChecker.checkMarketState(res, state);
        assert(res.underlying.balanceOf(thirdPeople) == 0);
        assert(res.collateral.balanceOf(thirdPeople) == 0);

        (address owner, uint128 d, , bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt + addedCollateral == abi.decode(cd, (uint256)));
        vm.stopPrank();
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

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        vm.stopPrank();

        address thirdPeople = vm.randomAddress();
        vm.warp(marketConfig.maturity);
        res.collateral.mint(thirdPeople, addedCollateral);

        vm.startPrank(thirdPeople);
        res.collateral.approve(address(res.gt), addedCollateral);

        vm.expectRevert(
            abi.encodeWithSelector(IGearingToken.GtIsExpired.selector, gtId)
        );

        res.gt.addCollateral(gtId, abi.encode(addedCollateral));
        vm.stopPrank();
    }

    function testRemoveCollateral() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        uint256 removedCollateral = 0.1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        uint collateralBlanceBefore = res.collateral.balanceOf(sender);

        vm.expectEmit();
        emit IGearingToken.RemoveCollateral(
            gtId,
            abi.encode(collateralAmt - removedCollateral)
        );
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));

        state.collateralReserve -= removedCollateral;
        StateChecker.checkMarketState(res, state);

        uint collateralBlanceAfter = res.collateral.balanceOf(sender);

        assert(
            collateralBlanceAfter - collateralBlanceBefore == removedCollateral
        );

        (address owner, uint128 d, , bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt - removedCollateral == abi.decode(cd, (uint256)));

        vm.stopPrank();
    }

    function testRevertByGtIsNotHealthyWhenRemoveCollateral() public {
        // debt 1780 USD collaretal 2200USD
        uint128 debtAmt = 1780e8;
        uint256 collateralAmt = 1.1e18;
        uint256 removedCollateral = 0.1e18;
        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.GtIsNotHealthy.selector,
                gtId,
                sender,
                LoanUtils.calcLtv(
                    res,
                    debtAmt,
                    collateralAmt - removedCollateral
                )
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

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();

        address thirdPeople = vm.randomAddress();
        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.CallerIsNotTheOwner.selector,
                gtId
            )
        );
        vm.prank(thirdPeople);
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));
    }

    function testRevertByGtIsExpiredWhenRemoveCollateral() public {
        // debt 200 USD collaretal 2200USD
        uint128 debtAmt = 200e8;
        uint256 collateralAmt = 1.1e18;
        uint256 removedCollateral = 0.1e18;
        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        vm.stopPrank();

        vm.warp(marketConfig.maturity);

        vm.expectRevert(
            abi.encodeWithSelector(IGearingToken.GtIsExpired.selector, gtId)
        );
        vm.prank(sender);
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));
    }

    function testRevertByDebtValueIsTooSmallWhenRemoveCollateral() public {
        uint128 debtAmt = 200e8;
        uint128 repayAmt = 199e8;
        uint256 collateralAmt = 1.1e18;
        uint256 removedCollateral = 0.1e18;
        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        res.underlying.mint(sender, repayAmt);
        res.underlying.approve(address(res.gt), repayAmt);
        res.gt.repay(gtId, repayAmt, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.DebtValueIsTooSmall.selector,
                debtAmt - repayAmt
            )
        );
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));

        vm.stopPrank();
    }

    // Case 1: removed collateral can not cover repayAmt + rewardToLiquidator
    function testLiquidateCase1() public {
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, debtAmt);
        res.underlying.approve(address(res.gt), debtAmt);

        uint senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        uint cToLiquidator = collateralAmt;
        uint cToTreasurer = 0;
        uint remainningC = 0;
        emit IGearingToken.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt);
        state.collateralReserve -= collateralAmt;
        state.underlyingReserve += debtAmt;
        StateChecker.checkMarketState(res, state);

        assert(
            res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer
        );
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(
            res.collateral.balanceOf(sender) ==
                remainningC + senderCBalanceBefore
        );
        vm.stopPrank();
    }

    // Case 2: removed collateral can cover repayAmt + rewardToLiquidator but not rewardToProtocol
    function testLiquidateCase2() public {
        uint128 debtAmt = 950e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, debtAmt);
        res.underlying.approve(address(res.gt), debtAmt);

        uint senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        // uint cToLiquidator = 0.9975e18;
        // uint cToTreasurer = 0.0025e18;
        // uint remainningC = 0;
        (uint cToLiquidator, uint cToTreasurer, uint remainningC) = LoanUtils
            .calcLiquidationResult(res, debtAmt, collateralAmt, debtAmt);
        emit IGearingToken.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt);
        state.collateralReserve -= collateralAmt;
        state.underlyingReserve += debtAmt;
        StateChecker.checkMarketState(res, state);

        assert(
            res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer
        );
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(
            res.collateral.balanceOf(sender) ==
                remainningC + senderCBalanceBefore
        );
        vm.stopPrank();
    }

    // Case 3: removed collateral equal repayAmt + rewardToLiquidator + rewardToProtocol
    function testLiquidateCase3() public {
        uint128 debtAmt = 900e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, debtAmt);
        res.underlying.approve(address(res.gt), debtAmt);

        uint senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        // uint cToLiquidator = 0.945e18;
        // uint cToTreasurer = 0.045e18;
        // uint remainningC = 0.01e18;
        (uint cToLiquidator, uint cToTreasurer, uint remainningC) = LoanUtils
            .calcLiquidationResult(res, debtAmt, collateralAmt, debtAmt);
        emit IGearingToken.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt);
        state.collateralReserve -= collateralAmt;
        state.underlyingReserve += debtAmt;
        StateChecker.checkMarketState(res, state);

        assert(
            res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer
        );
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(
            res.collateral.balanceOf(sender) ==
                remainningC + senderCBalanceBefore
        );
        vm.stopPrank();
    }

    function testRemovedCollateralLessThanRepayAmt() public {
        uint128 debtAmt = 900e8;
        uint256 collateralAmt = 0.93e18;
        uint128 repayAmt = 300e8;
        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, repayAmt);
        res.underlying.approve(address(res.gt), repayAmt);

        uint senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        // uint cToLiquidator = 0.31e18;
        // uint cToTreasurer = 0;
        // uint remainningC = 0.62e18;
        (uint cToLiquidator, uint cToTreasurer, uint remainningC) = LoanUtils
            .calcLiquidationResult(res, debtAmt, collateralAmt, repayAmt);
        emit IGearingToken.Liquidate(
            gtId,
            liquidator,
            repayAmt,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, repayAmt);
        state.collateralReserve -= (cToLiquidator + cToTreasurer);
        state.underlyingReserve += repayAmt;
        StateChecker.checkMarketState(res, state);

        assert(
            res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer
        );
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == senderCBalanceBefore);
        vm.stopPrank();
    }

    function testHalfLiquidate() public {
        uint128 debtAmt = 9000e8;
        uint256 collateralAmt = 10e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();
        (bool isLiquidable, uint128 maxRepayAmt) = res.gt.getLiquidationInfo(
            gtId
        );
        assert(isLiquidable);
        assert(maxRepayAmt == debtAmt / 2);
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, maxRepayAmt);
        res.underlying.approve(address(res.gt), maxRepayAmt);

        uint senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        // uint cToLiquidator = 4.725e18;
        // uint cToTreasurer = 0.225e18;
        // uint remainningC = 5.05e18;
        (uint cToLiquidator, uint cToTreasurer, uint remainningC) = LoanUtils
            .calcLiquidationResult(res, debtAmt, collateralAmt, maxRepayAmt);
        emit IGearingToken.Liquidate(
            gtId,
            liquidator,
            maxRepayAmt,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, maxRepayAmt);
        state.collateralReserve -= (cToLiquidator + cToTreasurer);
        state.underlyingReserve += maxRepayAmt;
        StateChecker.checkMarketState(res, state);

        assert(
            res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer
        );
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(res.collateral.balanceOf(sender) == senderCBalanceBefore);
        vm.stopPrank();

        (
            address owner,
            uint128 newDebtAmt,
            uint128 ltv,
            bytes memory collateralData
        ) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(newDebtAmt == debtAmt - maxRepayAmt);
        assert(ltv < liquidationLtv);
        assert(remainningC == abi.decode(collateralData, (uint)));

        (isLiquidable, maxRepayAmt) = res.gt.getLiquidationInfo(gtId);
        assert(!isLiquidable);
        assert(maxRepayAmt == 0);
    }

    function testLiquidateInWindowTime(uint16 exceedTime) public {
        uint liquidateTime = marketConfig.maturity + exceedTime;
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();

        vm.warp(liquidateTime);
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, debtAmt);
        res.underlying.approve(address(res.gt), debtAmt);

        uint senderCBalanceBefore = res.collateral.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        uint cToLiquidator = collateralAmt;
        uint cToTreasurer = 0;
        uint remainningC = 0;
        emit IGearingToken.Liquidate(
            gtId,
            liquidator,
            debtAmt,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );

        res.gt.liquidate(gtId, debtAmt);
        state.collateralReserve -= collateralAmt;
        state.underlyingReserve += debtAmt;
        StateChecker.checkMarketState(res, state);

        assert(
            res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer
        );
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);
        assert(
            res.collateral.balanceOf(sender) ==
                remainningC + senderCBalanceBefore
        );
        vm.stopPrank();
    }

    function testLiquidatable() public {
        uint128 debtAmt = 10000e8;
        uint256 collateralAmt = 10e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();

        vm.warp(marketConfig.maturity - 1);
        (bool isLiquidable, uint128 maxRepayAmt) = res.gt.getLiquidationInfo(
            gtId
        );
        assert(isLiquidable);
        assert(maxRepayAmt == debtAmt / 2);

        vm.warp(marketConfig.maturity);
        (isLiquidable, maxRepayAmt) = res.gt.getLiquidationInfo(gtId);
        assert(isLiquidable);
        assert(maxRepayAmt == debtAmt);

        vm.warp(marketConfig.maturity + Constants.LIQUIDATION_WINDOW);
        (isLiquidable, maxRepayAmt) = res.gt.getLiquidationInfo(gtId);
        assert(!isLiquidable);
        assert(maxRepayAmt == 0);
    }

    function testRevertByGtIsSafeWhenLiquidate() public {
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();

        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, debtAmt);
        res.underlying.approve(address(res.gt), debtAmt);

        vm.expectRevert(
            abi.encodeWithSelector(IGearingToken.GtIsSafe.selector, gtId)
        );
        res.gt.liquidate(gtId, debtAmt);

        vm.stopPrank();
    }

    function testRevertByGtDoNotSupportLiquidation() public {
        DeployUtils.Res memory rt;
        {
            vm.startPrank(deployer);
            vm.warp(marketConfig.openTime - 3600);
            rt = DeployUtils.deploySpecialMarket(
                deployer,
                res.factory,
                DeployUtils.GT_ERC20,
                marketConfig,
                maxLtv,
                liquidationLtv,
                false
            );

            vm.warp(
                vm.parseUint(
                    vm.parseJsonString(testdata, ".marketConfig.currentTime")
                )
            );

            // update oracle
            rt.collateralOracle.updateRoundData(
                JSONLoader.getRoundDataFromJson(
                    testdata,
                    ".priceData.ETH_2000_DAI_1.eth"
                )
            );
            rt.underlyingOracle.updateRoundData(
                JSONLoader.getRoundDataFromJson(
                    testdata,
                    ".priceData.ETH_2000_DAI_1.dai"
                )
            );

            uint amount = 10000e8;
            rt.underlying.mint(deployer, amount);
            rt.underlying.approve(address(rt.market), amount);
            rt.market.provideLiquidity(amount);

            vm.stopPrank();
        }

        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            rt,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();

        vm.startPrank(deployer);
        // update oracle
        rt.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        rt.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();

        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        rt.underlying.mint(liquidator, debtAmt);
        rt.underlying.approve(address(rt.gt), debtAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.GtDoNotSupportLiquidation.selector
            )
        );
        rt.gt.liquidate(gtId, debtAmt);

        vm.stopPrank();
    }

    function testRevertByCanNotLiquidationAfterFinalDeadline() public {
        uint liquidateTime = marketConfig.maturity +
            Constants.LIQUIDATION_WINDOW;
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();

        vm.warp(liquidateTime);
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, debtAmt);
        res.underlying.approve(address(res.gt), debtAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.CanNotLiquidationAfterFinalDeadline.selector,
                gtId,
                marketConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        res.gt.liquidate(gtId, debtAmt);
    }

    function testRevertByRepayAmtExceedsMaxRepayAmt() public {
        uint128 debtAmt = 9000e8;
        uint256 collateralAmt = 10e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();
        (bool isLiquidable, uint128 maxRepayAmt) = res.gt.getLiquidationInfo(
            gtId
        );
        assert(isLiquidable);
        assert(maxRepayAmt == debtAmt / 2);
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        uint128 repayAmt = maxRepayAmt + 1;
        res.underlying.mint(liquidator, repayAmt);
        res.underlying.approve(address(res.gt), repayAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.RepayAmtExceedsMaxRepayAmt.selector,
                gtId,
                repayAmt,
                maxRepayAmt
            )
        );
        res.gt.liquidate(gtId, repayAmt);

        vm.stopPrank();
    }

    function testNoRevertByLtvIncreasedAfterLiquidation(
        uint128 repayAmt
    ) public {
        uint128 debtAmt = 900e8;
        vm.assume(repayAmt >= 0 && repayAmt <= debtAmt);
        uint256 collateralAmt = 0.6e18;
        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();
        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, repayAmt);
        res.underlying.approve(address(res.gt), repayAmt);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        (uint cToLiquidator, uint cToTreasurer, uint remainningC) = LoanUtils
            .calcLiquidationResult(res, debtAmt, collateralAmt, repayAmt);
        emit IGearingToken.Liquidate(
            gtId,
            liquidator,
            repayAmt,
            abi.encode(cToLiquidator),
            abi.encode(cToTreasurer),
            abi.encode(remainningC)
        );
        res.gt.liquidate(gtId, repayAmt);
        if (repayAmt < debtAmt) {
            state.collateralReserve -= (cToLiquidator + cToTreasurer);
        } else {
            state.collateralReserve -= collateralAmt;
        }
        state.underlyingReserve += repayAmt;
        StateChecker.checkMarketState(res, state);

        assert(
            res.collateral.balanceOf(marketConfig.treasurer) == cToTreasurer
        );
        assert(res.collateral.balanceOf(liquidator) == cToLiquidator);

        vm.stopPrank();
    }

    function testRevertByDebtValueIsTooSmallWhenLiquidation() public {
        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;
        uint128 repayAmt = 999e8;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();

        vm.startPrank(deployer);
        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_1000_DAI_1.dai"
            )
        );
        vm.stopPrank();

        address liquidator = vm.randomAddress();
        vm.startPrank(liquidator);

        res.underlying.mint(liquidator, repayAmt);
        res.underlying.approve(address(res.gt), repayAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGearingToken.DebtValueIsTooSmall.selector,
                debtAmt - repayAmt
            )
        );
        res.gt.liquidate(gtId, repayAmt);

        vm.stopPrank();
    }
}
