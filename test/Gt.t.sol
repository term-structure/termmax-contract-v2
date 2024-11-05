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

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/testdata.json")
        );

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

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

        uint amount = 10000e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(amount);

        vm.stopPrank();
    }

    function testMintGtByIssueFt() public {
        vm.startPrank(deployer);
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
        vm.stopPrank();

        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);

        vm.startPrank(sender);

        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        (uint256 gtId, uint128 ftOutAmt) = res.market.issueFt(
            debtAmt,
            collateralData
        );
        uint issueFee = (debtAmt * marketConfig.issueFtfeeRatio) /
            Constants.DECIMAL_BASE;
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
        vm.startPrank(deployer);
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
        vm.stopPrank();

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
}
