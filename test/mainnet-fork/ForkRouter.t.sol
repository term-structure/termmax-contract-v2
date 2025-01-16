// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";

import {ITermMaxMarket, TermMaxMarket, Constants, TermMaxCurve} from "contracts/core/TermMaxMarket.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";

import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken} from "contracts/core/factory/TermMaxFactory.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import {MarketConfig} from "contracts/core/storage/TermMaxStorage.sol";
import {TermMaxRouter, ISwapAdapter, ITermMaxRouter, SwapUnit} from "contracts/router/TermMaxRouter.sol";
import {UniswapV3Adapter, ERC20SwapAdapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {OdosV2Adapter, IOdosRouterV2} from "contracts/router/swapAdapters/OdosV2Adapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    address odosRouter = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    UniswapV3Adapter uniswapAdapter;
    PendleSwapV3Adapter pendleAdapter;
    OdosV2Adapter odosAdapter;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21208075); // Nov-17-2024 05:09:23 PM +UTC, 1731388163

        uniswapAdapter = new UniswapV3Adapter(uniswapRouter);
        pendleAdapter = new PendleSwapV3Adapter(pendleRouter);
        odosAdapter = new OdosV2Adapter(odosRouter);

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
        
        MockPriceFeed.RoundData memory ptRoundData =JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_PT_WEETH_1800.ptWeeth"
            );
        ptRoundData.updatedAt = block.timestamp;
        res.collateralOracle.updateRoundData(ptRoundData);

        MockPriceFeed.RoundData memory weethRoundData =JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_PT_WEETH_1800.eth"
            );
        weethRoundData.updatedAt = block.timestamp; 
        res.underlyingOracle.updateRoundData(
            weethRoundData
        );

        uint amount = 10_000e18;
        deal(address(res.underlying), deployer, amount);

        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(uint128(amount));

        router = DeployUtils.deployRouter(deployer);
        router.setMarketWhitelist(address(res.market), true);

        router.setAdapterWhitelist(address(uniswapAdapter), true);
        router.setAdapterWhitelist(address(pendleAdapter), true);
        router.setAdapterWhitelist(address(odosAdapter), true);
        router.togglePause(false);

        vm.stopPrank();
    }

    function testLeverageFromXtWithUniswap() public {
        vm.startPrank(sender);
        uint128 underlyingAmtIn = 0.004e18;
        deal(address(res.underlying), sender, underlyingAmtIn);
        uint128 minTokenOut = 0e8;
        res.underlying.approve(address(router), underlyingAmtIn);

        uint256 underlyingAmtBeforeSwap = res.underlying.balanceOf(sender);
        uint256 xtAmtBeforeSwap = res.xt.balanceOf(sender);
        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        uint256 netXtOut = router.swapExactTokenForXt(
            receiver,
            res.market,
            underlyingAmtIn,
            minTokenOut,
            res.marketConfig.lsf
        );

        uint256 underlyingAmtAfterSwap = res.underlying.balanceOf(sender);
        uint256 xtAmtAfterSwap = res.xt.balanceOf(sender);

        assert(
            underlyingAmtBeforeSwap - underlyingAmtAfterSwap == underlyingAmtIn
        );
        assert(xtAmtAfterSwap - xtAmtBeforeSwap == netXtOut);
        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);

        uint256 xtInAmt = netXtOut;

        uint tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;

        deal(address(res.underlying), sender, tokenAmtIn);
        res.underlying.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](2);
        uint24 poolFee = 100;
        units[0] = SwapUnit(
            address(uniswapAdapter),
            weth9Addr,
            weethAddr,
            abi.encode(abi.encodePacked(weth9Addr, poolFee, weethAddr),block.timestamp + 3600, 0)
        );
        units[1] = SwapUnit(
            address(pendleAdapter),
            weethAddr,
            ptWeethAddr,
            abi.encode(ptWeethMarketAddr, 0)
        );

        underlyingAmtBeforeSwap = res.underlying.balanceOf(sender);
        xtAmtBeforeSwap = res.xt.balanceOf(sender);

        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        res.xt.approve(address(router), xtInAmt);
        router.leverageFromXt(
            receiver,
            res.market,
            xtInAmt,
            tokenAmtIn,
            maxLtv,
            units
        );

        underlyingAmtAfterSwap = res.underlying.balanceOf(sender);
        xtAmtAfterSwap = res.xt.balanceOf(sender);

        assert(underlyingAmtBeforeSwap - underlyingAmtAfterSwap == tokenAmtIn);
        assert(xtAmtBeforeSwap - xtAmtAfterSwap == xtInAmt);

        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        vm.stopPrank();
    }

    function testLeverageFromXtWithOdos() public {
        vm.startPrank(sender);
        uint128 underlyingAmtIn = 0.004e18;
        deal(address(res.underlying), sender, underlyingAmtIn);
        uint128 minTokenOut = 0e8;
        res.underlying.approve(address(router), underlyingAmtIn);

        uint256 underlyingAmtBeforeSwap = res.underlying.balanceOf(sender);
        uint256 xtAmtBeforeSwap = res.xt.balanceOf(sender);
        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        uint256 netXtOut = router.swapExactTokenForXt(
            receiver,
            res.market,
            underlyingAmtIn,
            minTokenOut,
            res.marketConfig.lsf
        );

        uint256 underlyingAmtAfterSwap = res.underlying.balanceOf(sender);
        uint256 xtAmtAfterSwap = res.xt.balanceOf(sender);

        assert(
            underlyingAmtBeforeSwap - underlyingAmtAfterSwap == underlyingAmtIn
        );
        assert(xtAmtAfterSwap - xtAmtBeforeSwap == netXtOut);
        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);

        uint256 xtInAmt = netXtOut;

        uint tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;

        deal(address(res.underlying), sender, tokenAmtIn);
        res.underlying.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](2);
        IOdosRouterV2.swapTokenInfo memory swapTokenInfoParam = IOdosRouterV2.swapTokenInfo(
            address(weth9Addr),
            tokenAmtIn,
            address(0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5),
            address(weethAddr),
            9455438286641436672,
            9360883903775023104,
            address(router)
        );
        address odosExecutor = 0xB28Ca7e465C452cE4252598e0Bc96Aeba553CF82;
        uint32 odosReferralCode = 0;
        bytes memory odosSwapData = abi.encode(
            swapTokenInfoParam,
            hex"010203000a01010001020001ff00000000000000000000000000000000000000db74dfdd3bb46be8ce6c33dc9d82777bcfc3ded5c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
            odosExecutor,
            odosReferralCode
        );
        units[0] = SwapUnit(
            address(odosAdapter),
            weth9Addr,
            weethAddr,
            odosSwapData
        );
        units[1] = SwapUnit(
            address(pendleAdapter),
            weethAddr,
            ptWeethAddr,
            abi.encode(ptWeethMarketAddr, 0)
        );

        underlyingAmtBeforeSwap = res.underlying.balanceOf(sender);
        xtAmtBeforeSwap = res.xt.balanceOf(sender);

        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        res.xt.approve(address(router), xtInAmt);
        router.leverageFromXt(
            receiver,
            res.market,
            xtInAmt,
            tokenAmtIn,
            maxLtv,
            units
        );

        underlyingAmtAfterSwap = res.underlying.balanceOf(sender);
        xtAmtAfterSwap = res.xt.balanceOf(sender);

        assert(underlyingAmtBeforeSwap - underlyingAmtAfterSwap == tokenAmtIn);
        assert(xtAmtBeforeSwap - xtAmtAfterSwap == xtInAmt);

        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        vm.stopPrank();
    }

    function testLeverageFromXtWhenPartialSwap() public {
        vm.startPrank(sender);
        uint128 underlyingAmtIn = 0.004e18;
        deal(address(res.underlying), sender, underlyingAmtIn);
        uint128 minTokenOut = 0e8;
        res.underlying.approve(address(router), underlyingAmtIn);

        uint256 netXtOut = router.swapExactTokenForXt(
            receiver,
            res.market,
            underlyingAmtIn,
            minTokenOut,
            res.marketConfig.lsf
        );

        uint256 xtInAmt = netXtOut;

        uint tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;

        deal(address(res.underlying), sender, tokenAmtIn);
        res.underlying.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](2);
        uint24 poolFee = 3000;
        units[0] = SwapUnit(
            address(uniswapAdapter),
            weth9Addr,
            weethAddr,
            abi.encode(abi.encodePacked(weth9Addr, poolFee, weethAddr), block.timestamp + 3600, 0)
        );
        units[1] = SwapUnit(
            address(pendleAdapter),
            weethAddr,
            ptWeethAddr,
            abi.encode(ptWeethMarketAddr, 0)
        );

        res.xt.approve(address(router), xtInAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxRouter.SwapFailed.selector,
                address(uniswapAdapter),
                abi.encodePacked(
                    abi.encodeWithSelector(
                        ERC20SwapAdapter.ERC20InvalidPartialSwap.selector,
                        tokenAmtIn + xtInAmt,
                        uint(39902378112923432)
                    )
                )
            )
        );
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
        uint24 poolFee = 100;
        _loan(poolFee);
        vm.stopPrank();
    }

    function testFlashRepay() public {
        vm.startPrank(sender);
        uint24 poolFee = 100;

        uint256 gtId = _loan(poolFee);
        (, uint128 debtAmt, ,) = res.gt.loanInfo(
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
            abi.encode(
                abi.encodePacked(weethAddr, poolFee, weth9Addr),
                block.timestamp + 3600,
                minUnderlyingAmt
            )
        );

        res.gt.approve(address(router), gtId);

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        uint256 underlyingAmtBeforeRepay = res.underlying.balanceOf(sender);

        uint256 netTokenOut = router.flashRepayFromColl(
            sender,
            res.market,
            gtId,
            true,
            units,
            res.marketConfig.lsf
        );

        uint256 underlyingAmtAfterRepay = res.underlying.balanceOf(sender);

        assert(
            underlyingAmtAfterRepay - underlyingAmtBeforeRepay == netTokenOut
        );

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        vm.stopPrank();
    }

    function testFlashRepayByFt() public {
        vm.startPrank(sender);
        uint24 poolFee = 100;

        uint256 gtId = _loan(poolFee);
        (, uint128 debtAmt, ,) = res.gt.loanInfo(
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
            abi.encode(
                abi.encodePacked(weethAddr, poolFee, weth9Addr),
                minUnderlyingAmt
            )
        );

        res.gt.approve(address(router), gtId);

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        uint256 underlyingAmtBeforeRepay = res.underlying.balanceOf(sender);

        uint256 netTokenOut = router.flashRepayFromColl(
            sender,
            res.market,
            gtId,
            false,
            units,
            res.marketConfig.lsf
        );
        uint256 underlyingAmtAfterRepay = res.underlying.balanceOf(sender);
        assert(
            underlyingAmtAfterRepay - underlyingAmtBeforeRepay == netTokenOut
        );

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        vm.stopPrank();
    }

    function _loan(uint24 poolFee) internal returns (uint256 gtId) {
        uint128 underlyingAmtInForBuyXt = 1e18;
        uint256 tokenInAmt = 2e18;
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
            abi.encode(abi.encodePacked(weth9Addr, poolFee, weethAddr), block.timestamp + 3600, 0)
        );
        units[1] = SwapUnit(
            address(pendleAdapter),
            weethAddr,
            ptWeethAddr,
            abi.encode(ptWeethMarketAddr, 0)
        );

        uint256 underlyingAmtBeforeSwap = res.underlying.balanceOf(sender);

        assert(res.collateral.balanceOf(address(sender)) == 0);
        assert(res.xt.balanceOf(address(sender)) == 0);
        assert(res.ft.balanceOf(address(sender)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        (gtId, ) = router.leverageFromToken(
            receiver,
            res.market,
            tokenInAmt,
            underlyingAmtInForBuyXt,
            maxLtv,
            minXTOut,
            units,
            res.marketConfig.lsf
        );

        uint256 underlyingAmtAfterSwap = res.underlying.balanceOf(sender);

        assert(
            underlyingAmtBeforeSwap - underlyingAmtAfterSwap ==
                underlyingAmtInForBuyXt + tokenInAmt
        );

        assert(res.collateral.balanceOf(address(sender)) == 0);
        assert(res.xt.balanceOf(address(sender)) == 0);
        assert(res.ft.balanceOf(address(sender)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.underlying.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);
    }
}
