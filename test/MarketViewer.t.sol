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
import {MockFlashRepayer} from "../contracts/test/MockFlashRepayer.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {AbstractGearingToken} from "../contracts/core/tokens/AbstractGearingToken.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken} from "../contracts/core/factory/TermMaxFactory.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import "../contracts/core/storage/TermMaxStorage.sol";
import {MarketViewer} from "../contracts/router/MarketViewer.sol";
import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";

contract MarketViewerTest is Test {
    using JSONLoader for *;
    using SafeCast for uint256;
    using SafeCast for int256;

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    DeployUtils.Res res;

    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    MockFlashLoanReceiver flashLoanReceiver;

    MockFlashRepayer flashRepayer;

    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;

    TermMaxRouter router;
    MarketViewer viewer;

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
        flashRepayer = new MockFlashRepayer(res.gt);
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
        res.market.provideLiquidity(uint128(amount));

        router = DeployUtils.deployRouter(deployer);
        router.setMarketWhitelist(address(res.market), true);
        router.togglePause(false);

        viewer = new MarketViewer();

        vm.stopPrank();
    }

    function testGetPositionDetail() public {
        vm.startPrank(sender);
        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        router.swapExactTokenForFt(
            sender,
            res.market,
            underlyingAmtIn,
            minTokenOut
        );

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        router.swapExactTokenForXt(
                sender,
                res.market,
                underlyingAmtIn,
                minTokenOut
            );

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        res.market.provideLiquidity(underlyingAmtIn);


        uint128 debtAmt = 100e8;
        uint256 loanCollateralAmt = 1e18;
        res.collateral.mint(sender, loanCollateralAmt);
        res.collateral.approve(address(res.gt), loanCollateralAmt);

        bytes memory collateralData = abi.encode(loanCollateralAmt);
        (uint256 gtId,) = res.market.issueFt(
            debtAmt,
            collateralData
        );

        uint256 underlyingAmt = 123e8;
        uint256 collateralAmt = 1e18;
        res.underlying.mint(sender, underlyingAmt);
        res.collateral.mint(sender, collateralAmt);

        MarketViewer.Position memory Position = viewer.getPositionDetail(res.market, sender);
        
        assert(Position.underlyingBalance == underlyingAmt);
        assert(Position.collateralBalance == collateralAmt);
        assert(Position.ftBalance == res.ft.balanceOf(sender));
        assert(Position.xtBalance == res.xt.balanceOf(sender));
        assert(Position.lpFtBalance == res.lpFt.balanceOf(sender));
        assert(Position.lpXtBalance == res.lpXt.balanceOf(sender));
        assert(Position.gtInfo.length == 1);
        assert(Position.gtInfo[0].loanId == gtId);
        assert(Position.gtInfo[0].collateralAmt == loanCollateralAmt);
        assert(Position.gtInfo[0].debtAmt == debtAmt);

        vm.stopPrank();
    }
    
    function testGetAllLoanPosition() public {
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

        MarketViewer.LoanPosition[] memory gtInfos = viewer.getAllLoanPosition(res.market, sender);
        assert(gtInfos[0].loanId == gtId);
        assert(gtInfos[0].collateralAmt == collateralAmt);
        assert(gtInfos[0].debtAmt == debtAmt);

        vm.stopPrank();
    }
    
}
