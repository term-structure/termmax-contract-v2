// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";

import {ITermMaxMarket, TermMaxMarket, Constants, TermMaxCurve} from "contracts/core/TermMaxMarket.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";

import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "contracts/core/factory/TermMaxFactory.sol";
import {MarketConfig} from "contracts/core/storage/TermMaxStorage.sol";
import {TermMaxRouter, ISwapAdapter, ITermMaxRouter, SwapUnit} from "contracts/router/TermMaxRouter.sol";
import {UniswapV3Adapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";

contract ForkRouterTest is Test {
    address deployer = vm.randomAddress();

    DeployUtils.Res res;

    MarketConfig marketConfig;

    address sender = vm.randomAddress();
    address receiver = sender;

    address treasurer = vm.randomAddress();
    string testdata;
    ITermMaxRouter router;

    address weth9Addr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address weethAddr = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address ptWeethAddr = 0x6ee2b5E19ECBa773a352E5B21415Dc419A700d1d;
    address ptWeethMarketAddr = 0x7d372819240D14fB477f17b964f95F33BeB4c704; // 26 Dec 2024

    address pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint24 poolFee = 3000;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    UniswapV3Adapter uniswapAdapter;
    PendleSwapV3Adapter pendleAdapter;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21208075); // Nov-17-2024 05:09:23 PM +UTC, 1731388163

        uniswapAdapter = new UniswapV3Adapter(uniswapRouter);
        pendleAdapter = new PendleSwapV3Adapter(pendleRouter);

        deal(deployer, 1_000e18);
        deal(sender, 1_000e18);
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
        // 1731854315 is the block time of block 21208075
        marketConfig.openTime = 1731854315 + 60;
        marketConfig.maturity = marketConfig.openTime + 30 days;

        vm.warp(marketConfig.openTime - 3600);

        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv,
            ptWeethAddr,
            weth9Addr
        );

        vm.warp(marketConfig.openTime + 3600);

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_PT_WEETH_1800.ptWeeth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_PT_WEETH_1800.eth"
            )
        );

        uint amount = 10_000e18;
        deal(address(res.underlying), deployer, amount);

        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(amount);

        router = DeployUtils.deployRouter(deployer);
        router.setMarketWhitelist(address(res.market), true);

        router.setAdapterWhitelist(address(uniswapAdapter), true);
        router.setAdapterWhitelist(address(pendleAdapter), true);
        router.togglePause(false);

        vm.stopPrank();
    }

    function testLeverageFromXt() public {
        vm.startPrank(sender);
        uint128 underlyingAmtIn = 0.004e18;
        deal(address(res.underlying), sender, underlyingAmtIn);
        uint128 minTokenOut = 0e8;
        res.underlying.approve(address(router), underlyingAmtIn);

        uint256 netXtOut = router.swapExactTokenForXt(
            receiver,
            res.market,
            underlyingAmtIn,
            minTokenOut
        );
        uint256 xtInAmt = netXtOut;

        uint tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;

        deal(address(res.underlying), sender, tokenAmtIn);
        res.underlying.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](2);

        units[0] = SwapUnit(
            address(uniswapAdapter),
            weth9Addr,
            weethAddr,
            abi.encode(poolFee, 0)
        );
        units[1] = SwapUnit(
            address(pendleAdapter),
            weethAddr,
            ptWeethAddr,
            abi.encode(ptWeethMarketAddr, 0)
        );

        res.xt.approve(address(router), xtInAmt);
        router.leverageFromXt(
            receiver,
            res.market,
            xtInAmt,
            tokenAmtIn,
            maxLtv,
            units
        );
        vm.stopPrank();
    }

    function testLeverageFromToken() public {
        vm.startPrank(sender);

        _loan();

        vm.stopPrank();
    }

    function testFlashRepay() public {
        vm.startPrank(sender);

        uint256 gtId = _loan();
        (, uint128 debtAmt, , bytes memory collateralData) = res.gt.loanInfo(
            gtId
        );

        uint256 minUnderlyingAmt = debtAmt;

        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(
            address(pendleAdapter),
            ptWeethAddr,
            weethAddr,
            abi.encode(ptWeethMarketAddr, 0)
        );
        units[1] = SwapUnit(
            address(uniswapAdapter),
            weethAddr,
            weth9Addr,
            abi.encode(poolFee, minUnderlyingAmt)
        );

        res.collateral.approve(
            address(router),
            abi.decode(collateralData, (uint))
        );
        router.flashRepayFromColl(sender, res.market, gtId, units);

        vm.stopPrank();
    }

    function _loan() internal returns (uint256 gtId) {
        uint128 underlyingAmtInForBuyXt = 0.004e18;
        uint256 tokenInAmt = 10e18;
        uint128 minXTOut = 0e8;
        uint256 maxLtv = 0.8e8;

        deal(
            address(res.underlying),
            sender,
            underlyingAmtInForBuyXt + tokenInAmt
        );
        res.underlying.approve(
            address(router),
            underlyingAmtInForBuyXt + tokenInAmt
        );

        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(
            address(uniswapAdapter),
            weth9Addr,
            weethAddr,
            abi.encode(poolFee, 0)
        );
        units[1] = SwapUnit(
            address(pendleAdapter),
            weethAddr,
            ptWeethAddr,
            abi.encode(ptWeethMarketAddr, 0)
        );

        (gtId, ) = router.leverageFromToken(
            receiver,
            res.market,
            tokenInAmt,
            underlyingAmtInForBuyXt,
            maxLtv,
            minXTOut,
            units
        );
    }
}
