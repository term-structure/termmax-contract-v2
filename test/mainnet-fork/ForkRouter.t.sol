// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Constants} from "contracts/lib/Constants.sol";
import {ITermMaxMarket, TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {IGearingToken, AbstractGearingToken} from "contracts/tokens/AbstractGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";
import {TermMaxRouter, ISwapAdapter, ITermMaxRouter, SwapUnit, RouterErrors} from "contracts/router/TermMaxRouter.sol";
import {UniswapV3Adapter, ERC20SwapAdapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {OdosV2Adapter, IOdosRouterV2} from "contracts/router/swapAdapters/OdosV2Adapter.sol";
import "contracts/storage/TermMaxStorage.sol";

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
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        // 1731854315 is the block time of block 21208075
        uint64 currentTime = uint64(1731854315);
        marketConfig.maturity = uint64(currentTime + 90 days);

        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv, ptWeethAddr, weth9Addr);

        // update oracle

        MockPriceFeed.RoundData memory ptRoundData = JSONLoader.getRoundDataFromJson(
            testdata,
            ".priceData.ETH_2000_PT_WEETH_1800.ptWeeth"
        );
        ptRoundData.updatedAt = currentTime;
        res.collateralOracle.updateRoundData(ptRoundData);

        MockPriceFeed.RoundData memory weethRoundData = JSONLoader.getRoundDataFromJson(
            testdata,
            ".priceData.ETH_2000_PT_WEETH_1800.eth"
        );
        weethRoundData.updatedAt = currentTime;
        res.debtOracle.updateRoundData(weethRoundData);

        // init order
        OrderConfig memory orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");
        orderConfig.maxXtReserve = type(uint128).max;
        res.order = res.market.createOrder(
            vm.randomAddress(),
            orderConfig.maxXtReserve,
            ISwapCallback(address(0)),
            orderConfig.curveCuts
        );

        uint amount = 15000e8;
        deal(address(res.debt), deployer, amount);

        res.debt.approve(address(res.market), amount);
        res.market.mint(address(res.order), amount);

        router = DeployUtils.deployRouter(deployer);
        router.setMarketWhitelist(address(res.market), true);

        router.setAdapterWhitelist(address(uniswapAdapter), true);
        router.setAdapterWhitelist(address(pendleAdapter), true);
        router.setAdapterWhitelist(address(odosAdapter), true);

        vm.stopPrank();
    }

    function testLeverageFromXtWithUniswap() public {
        vm.startPrank(sender);
        uint128 underlyingAmtIn = 0.004e18;
        deal(address(res.debt), sender, underlyingAmtIn);
        uint128 minTokenOut = 0e8;
        res.debt.approve(address(router), underlyingAmtIn);

        uint256 underlyingAmtBeforeSwap = res.debt.balanceOf(sender);
        uint256 xtAmtBeforeSwap = res.xt.balanceOf(sender);
        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 5e8;
        uint256 netXtOut = router.swapExactTokenToToken(
            res.debt,
            res.ft,
            receiver,
            orders,
            amounts,
            uint128(minTokenOut)
        );
        uint256 underlyingAmtAfterSwap = res.debt.balanceOf(sender);
        uint256 xtAmtAfterSwap = res.xt.balanceOf(sender);

        assert(underlyingAmtBeforeSwap - underlyingAmtAfterSwap == underlyingAmtIn);
        assert(xtAmtAfterSwap - xtAmtBeforeSwap == netXtOut);
        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);

        uint256 xtInAmt = netXtOut;

        uint tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;

        deal(address(res.debt), sender, tokenAmtIn);
        res.debt.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](2);
        uint24 poolFee = 100;
        units[0] = SwapUnit(
            address(uniswapAdapter),
            weth9Addr,
            weethAddr,
            abi.encode(abi.encodePacked(weth9Addr, poolFee, weethAddr), block.timestamp + 3600, 0)
        );
        units[1] = SwapUnit(address(pendleAdapter), weethAddr, ptWeethAddr, abi.encode(ptWeethMarketAddr, 0));

        underlyingAmtBeforeSwap = res.debt.balanceOf(sender);
        xtAmtBeforeSwap = res.xt.balanceOf(sender);

        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        res.xt.approve(address(router), xtInAmt);
        router.leverageFromXt(receiver, res.market, uint128(xtInAmt), uint128(tokenAmtIn), uint128(maxLtv), units);

        underlyingAmtAfterSwap = res.debt.balanceOf(sender);
        xtAmtAfterSwap = res.xt.balanceOf(sender);

        assert(underlyingAmtBeforeSwap - underlyingAmtAfterSwap == tokenAmtIn);
        assert(xtAmtBeforeSwap - xtAmtAfterSwap == xtInAmt);

        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        vm.stopPrank();
    }

    function testLeverageFromXtWithOdos() public {
        vm.startPrank(sender);
        uint128 underlyingAmtIn = 0.004e18;
        deal(address(res.debt), sender, underlyingAmtIn);
        uint128 minTokenOut = 0e8;
        res.debt.approve(address(router), underlyingAmtIn);

        uint256 underlyingAmtBeforeSwap = res.debt.balanceOf(sender);
        uint256 xtAmtBeforeSwap = res.xt.balanceOf(sender);
        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 5e8;
        uint256 netXtOut = router.swapExactTokenToToken(
            res.debt,
            res.ft,
            receiver,
            orders,
            amounts,
            uint128(minTokenOut)
        );

        uint256 underlyingAmtAfterSwap = res.debt.balanceOf(sender);
        uint256 xtAmtAfterSwap = res.xt.balanceOf(sender);

        assert(underlyingAmtBeforeSwap - underlyingAmtAfterSwap == underlyingAmtIn);
        assert(xtAmtAfterSwap - xtAmtBeforeSwap == netXtOut);
        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);

        uint256 xtInAmt = netXtOut;

        uint tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;

        deal(address(res.debt), sender, tokenAmtIn);
        res.debt.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](2);

        // Note: reference Odos docs: https://docs.odos.xyz/build/api-docs
        address odosInputReceiver = address(0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5); // Curve pool weETH/WETH
        uint256 outputQuote = 9455438286641436672;
        uint256 outputMin = 9360883903775023104;
        IOdosRouterV2.swapTokenInfo memory swapTokenInfoParam = IOdosRouterV2.swapTokenInfo(
            address(weth9Addr),
            tokenAmtIn,
            address(odosInputReceiver),
            address(weethAddr),
            outputQuote,
            outputMin,
            address(router)
        );
        address odosExecutor = 0xB28Ca7e465C452cE4252598e0Bc96Aeba553CF82;
        bytes
            memory odosPath = hex"010203000a01010001020001ff00000000000000000000000000000000000000db74dfdd3bb46be8ce6c33dc9d82777bcfc3ded5c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
        uint32 odosReferralCode = 0;
        bytes memory odosSwapData = abi.encode(swapTokenInfoParam, odosPath, odosExecutor, odosReferralCode);
        units[0] = SwapUnit(address(odosAdapter), weth9Addr, weethAddr, odosSwapData);
        units[1] = SwapUnit(address(pendleAdapter), weethAddr, ptWeethAddr, abi.encode(ptWeethMarketAddr, 0));

        underlyingAmtBeforeSwap = res.debt.balanceOf(sender);
        xtAmtBeforeSwap = res.xt.balanceOf(sender);

        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        res.xt.approve(address(router), xtInAmt);

        router.leverageFromXt(receiver, res.market, uint128(xtInAmt), uint128(tokenAmtIn), uint128(maxLtv), units);

        underlyingAmtAfterSwap = res.debt.balanceOf(sender);
        xtAmtAfterSwap = res.xt.balanceOf(sender);

        assert(underlyingAmtBeforeSwap - underlyingAmtAfterSwap == tokenAmtIn);
        assert(xtAmtBeforeSwap - xtAmtAfterSwap == xtInAmt);

        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        vm.stopPrank();
    }

    function testLeverageFromXtWhenPartialSwap() public {
        vm.startPrank(sender);
        uint128 underlyingAmtIn = 0.004e18;
        deal(address(res.debt), sender, underlyingAmtIn);
        uint128 minTokenOut = 0e8;
        res.debt.approve(address(router), underlyingAmtIn);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 5e8;
        uint256 netXtOut = router.swapExactTokenToToken(
            res.debt,
            res.ft,
            receiver,
            orders,
            amounts,
            uint128(minTokenOut)
        );

        uint256 xtInAmt = netXtOut;

        uint tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;

        deal(address(res.debt), sender, tokenAmtIn);
        res.debt.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](2);
        uint24 poolFee = 3000;
        units[0] = SwapUnit(
            address(uniswapAdapter),
            weth9Addr,
            weethAddr,
            abi.encode(abi.encodePacked(weth9Addr, poolFee, weethAddr), block.timestamp + 3600, 0)
        );
        units[1] = SwapUnit(address(pendleAdapter), weethAddr, ptWeethAddr, abi.encode(ptWeethMarketAddr, 0));

        res.xt.approve(address(router), xtInAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                RouterErrors.SwapFailed.selector,
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
        router.leverageFromXt(receiver, res.market, uint128(xtInAmt), uint128(tokenAmtIn), uint128(maxLtv), units);

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
        (, uint128 debtAmt, , ) = res.gt.loanInfo(gtId);

        uint256 minUnderlyingAmt = debtAmt;

        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(address(pendleAdapter), ptWeethAddr, weethAddr, abi.encode(ptWeethMarketAddr, 0));

        units[1] = SwapUnit(
            address(uniswapAdapter),
            weethAddr,
            weth9Addr,
            abi.encode(abi.encodePacked(weethAddr, poolFee, weth9Addr), block.timestamp + 3600, minUnderlyingAmt)
        );

        res.gt.approve(address(router), gtId);

        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        uint256 underlyingAmtBeforeRepay = res.debt.balanceOf(sender);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](0);
        uint128[] memory amtsToBuyFt = new uint128[](0);
        bool byDebtToken = true;

        uint256 netTokenOut = router.flashRepayFromColl(
            sender,
            res.market,
            gtId,
            orders,
            amtsToBuyFt,
            byDebtToken,
            units
        );

        uint256 underlyingAmtAfterRepay = res.debt.balanceOf(sender);

        assert(underlyingAmtAfterRepay - underlyingAmtBeforeRepay == netTokenOut);

        assert(res.debt.balanceOf(address(router)) == 0);
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
        (, uint128 debtAmt, , ) = res.gt.loanInfo(gtId);

        uint256 minUnderlyingAmt = debtAmt;

        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(address(pendleAdapter), ptWeethAddr, weethAddr, abi.encode(ptWeethMarketAddr, 0));

        units[1] = SwapUnit(
            address(uniswapAdapter),
            weethAddr,
            weth9Addr,
            abi.encode(abi.encodePacked(weethAddr, poolFee, weth9Addr), minUnderlyingAmt)
        );

        res.gt.approve(address(router), gtId);

        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        uint256 underlyingAmtBeforeRepay = res.debt.balanceOf(sender);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory amtsToBuyFt = new uint128[](1);
        amtsToBuyFt[0] = debtAmt;
        bool byDebtToken = false;

        uint256 netTokenOut = router.flashRepayFromColl(
            sender,
            res.market,
            gtId,
            orders,
            amtsToBuyFt,
            byDebtToken,
            units
        );

        uint256 underlyingAmtAfterRepay = res.debt.balanceOf(sender);
        assert(underlyingAmtAfterRepay - underlyingAmtBeforeRepay == netTokenOut);

        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weth9Addr).balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        vm.stopPrank();
    }

    function _loan(uint24 poolFee) internal returns (uint256 gtId) {
        uint128 underlyingAmtInForBuyXt = 5e8;
        uint256 tokenInAmt = 2e18;
        uint128 minXTOut = 0e8;
        uint256 maxLtv = 0.8e8;

        deal(address(res.debt), sender, underlyingAmtInForBuyXt + tokenInAmt);
        res.debt.approve(address(router), underlyingAmtInForBuyXt + tokenInAmt);
        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(
            address(uniswapAdapter),
            weth9Addr,
            weethAddr,
            abi.encode(abi.encodePacked(weth9Addr, poolFee, weethAddr), block.timestamp + 3600, 0)
        );
        units[1] = SwapUnit(address(pendleAdapter), weethAddr, ptWeethAddr, abi.encode(ptWeethMarketAddr, 0));

        uint256 underlyingAmtBeforeSwap = res.debt.balanceOf(sender);

        assert(res.collateral.balanceOf(address(sender)) == 0);
        assert(res.xt.balanceOf(address(sender)) == 0);
        assert(res.ft.balanceOf(address(sender)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory amtsToBuyXt = new uint128[](1);
        amtsToBuyXt[0] = underlyingAmtInForBuyXt;
        (gtId, ) = router.leverageFromToken(
            receiver,
            res.market,
            orders,
            amtsToBuyXt,
            uint128(minXTOut),
            uint128(tokenInAmt),
            uint128(maxLtv),
            units
        );

        uint256 underlyingAmtAfterSwap = res.debt.balanceOf(sender);

        assert(underlyingAmtBeforeSwap - underlyingAmtAfterSwap == underlyingAmtInForBuyXt + tokenInAmt);

        assert(res.collateral.balanceOf(address(sender)) == 0);
        assert(res.xt.balanceOf(address(sender)) == 0);
        assert(res.ft.balanceOf(address(sender)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(sender)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(sender)) == 0);

        assert(res.debt.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);
    }
}
