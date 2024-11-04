// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../contracts/core/factory/TermMaxFactory.sol";
import "../contracts/core/storage/TermMaxStorage.sol";

contract SwapTest is Test {
    address deployer = vm.envAddress("FORK_DEPLOYER_ADDR");

    DeployUtils.Res res;

    MarketConfig marketConfig;

    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    function getMarketStateFromJson(
        string memory testdata,
        string memory key
    ) internal view returns (StateChecker.MarketState memory state) {
        address market = address(res.market);
        state.apr = vm.parseInt(
            vm.parseJsonString(testdata, string.concat(key, ".apr"))
        );
        state.ftReserve = vm.parseUint(
            vm.parseJsonString(testdata, string.concat(key, ".ftReserve"))
        );
        state.xtReserve = vm.parseUint(
            vm.parseJsonString(testdata, string.concat(key, ".xtReserve"))
        );
        state.lpFtReserve = vm.parseUint(
            vm.parseJsonString(testdata, string.concat(key, ".lpFtReserve"))
        );
        state.lpXtReserve = vm.parseUint(
            vm.parseJsonString(testdata, string.concat(key, ".lpXtReserve"))
        );
        state.underlyingReserve = vm.parseUint(
            vm.parseJsonString(
                testdata,
                string.concat(key, ".UnderlyingReserve")
            )
        );
        state.collateralReserve = vm.parseUint(
            vm.parseJsonString(
                testdata,
                string.concat(key, ".CollateralReserve")
            )
        );
    }

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/Swap.testdata.json")
        );

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig.openTime = uint64(
            vm.parseUint(vm.parseJsonString(testdata, ".marketConfig.openTime"))
        );
        marketConfig.maturity = uint64(
            vm.parseUint(vm.parseJsonString(testdata, ".marketConfig.maturity"))
        );
        marketConfig.initialLtv = uint32(
            vm.parseUint(
                vm.parseJsonString(testdata, ".marketConfig.initialLtv")
            )
        );
        marketConfig.apr = int64(
            vm.parseInt(vm.parseJsonString(testdata, ".marketConfig.apr"))
        );
        marketConfig.lsf = uint32(
            vm.parseUint(vm.parseJsonString(testdata, ".marketConfig.lsf"))
        );
        marketConfig.lendFeeRatio = uint32(
            vm.parseUint(
                vm.parseJsonString(testdata, ".marketConfig.lendFeeRatio")
            )
        );
        marketConfig.borrowFeeRatio = uint32(
            vm.parseUint(
                vm.parseJsonString(testdata, ".marketConfig.borrowFeeRatio")
            )
        );
        marketConfig.lockingFeeRatio = uint32(
            vm.parseUint(
                vm.parseJsonString(testdata, ".marketConfig.lockingFeeRatio")
            )
        );
        marketConfig.treasurer = treasurer;
        marketConfig.deliverable = true;
        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );

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

    //test init value?

    function testBuyFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        uint256 netOut = res.market.buyFt(underlyingAmtIn, minTokenOut);

        StateChecker.MarketState memory expectedState = getMarketStateFromJson(
            testdata,
            ".expected.testBuyFT.contractState"
        );

        /* FOR_DEBUG_START */
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        console.log("----");
        console.log(res.market.config().borrowFeeRatio);
        console.log("----");
        console.log(state.apr);
        console.log(state.ftReserve);
        console.log(state.xtReserve);
        console.log(state.lpFtReserve);
        console.log(state.lpXtReserve);
        console.log(state.underlyingReserve);
        console.log(state.collateralReserve);
        console.log("----");
        console.log(expectedState.apr);
        console.log(expectedState.ftReserve);
        console.log(expectedState.xtReserve);
        console.log(expectedState.lpFtReserve);
        console.log(expectedState.lpXtReserve);
        console.log(expectedState.underlyingReserve);
        console.log(expectedState.collateralReserve);
        /* FOR_DEBUG_END */

        StateChecker.checkMarketState(res, expectedState);

        vm.stopPrank();
    }

    // function testBuyFT() public {
    //     vm.startPrank(sender);
    //     // uint amount = 10000e8;
    //     (uint256 pFt, uint256 pXt) = SwapUtils.getPrice(res);
    //     console.log(pFt);
    //     console.log(pXt);
    //     console.log((pXt * 9) / 10 + pFt);

    //     vm.stopPrank();
    // }
}
