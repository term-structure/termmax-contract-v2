// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../contracts/core/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../contracts/core/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "../contracts/router/ITermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../contracts/core/TermMaxMarket.sol";
import {ITermMaxMarket} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20} from "../contracts/test/MockERC20.sol";
import {MarketConfig} from "../contracts/core/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../contracts/core/tokens/IMintableERC20.sol";
import {IGearingToken, AggregatorV3Interface} from "../contracts/core/tokens/IGearingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../contracts/test/MockSwapAdapter.sol";
import {Faucet} from "../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../contracts/test/testnet/FaucetERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {SwapUnit} from "../contracts/router/ISwapAdapter.sol";
import {MarketConfig} from "../contracts/core/storage/TermMaxStorage.sol";

contract E2ETest is Script {
    // deployer config
    uint256 userPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address userAddr = vm.addr(userPrivateKey);

    // address config
    address faucetAddr = address(0x1346C9F8e04ad7a33F47625e674e1449D1849A84);
    address routerAddr = address(0xd3c3DB013d1eC1004f7D03553662e03529DA92e6);
    address swapAdapter = address(0x3BB5734b9fEdd0e27913487e6370B9AFfec477Ca);
    address[] markets = [
        address(0x031138b4c90Abc8c7602D8514BD80B8f432eD990),
        address(0xa65Fc86A2094DEF29eFc128ed3B4BC73fDe0ca0d),
        address(0xCf7004758997fb7B5b0De50C8CD7a6407ebD7522)
    ];

    TermMaxMarket market;
    TermMaxRouter router;
    Faucet faucet;
    IMintableERC20 ft;
    IMintableERC20 xt;
    IMintableERC20 lpFt;
    IMintableERC20 lpXt;
    IGearingToken gt;
    address collateralAddr;
    FaucetERC20 collateral;
    FaucetERC20 underlying;
    IERC20 underlyingERC20;
    MockPriceFeed collateralPriceFeed;
    MockPriceFeed underlyingPriceFeed;
    MarketConfig config;

    function run() public {
        faucet = Faucet(faucetAddr);
        router = TermMaxRouter(routerAddr);

        vm.startBroadcast(userPrivateKey);
        // // provide liquidity
        for (uint i = 0; i < markets.length; i++) {
            address marketAddr = markets[i];
            market = TermMaxMarket(marketAddr);
            (ft, xt, lpFt, lpXt, gt, collateralAddr, underlyingERC20) = market
                .tokens();
            console.log("Market address", marketAddr);
            console.log("ft address", address(ft));
            console.log("xt address", address(xt));
            console.log("lpFt address", address(lpFt));
            console.log("lpXt address", address(lpXt));
            console.log("gt address", address(gt));
            console.log("collateral address", collateralAddr);
            console.log("underlying address", address(underlyingERC20));
            underlying = FaucetERC20(address(underlyingERC20));
            collateral = FaucetERC20(collateralAddr);

            underlyingPriceFeed = MockPriceFeed(
                faucet
                    .getTokenConfig(faucet.getTokenId(address(underlying)))
                    .priceFeedAddr
            );

            collateralPriceFeed = MockPriceFeed(
                faucet
                    .getTokenConfig(faucet.getTokenId(collateralAddr))
                    .priceFeedAddr
            );
            (, int256 ans, , , ) = underlyingPriceFeed.latestRoundData();
            uint256 underlyingPrice = uint256(ans);
            uint256 priceDecimalBase = 10 ** underlyingPriceFeed.decimals();
            uint256 amount = ((2000000 * priceDecimalBase) / underlyingPrice) *
                10 ** underlying.decimals();
            console.log(amount);
            faucet.devMint(userAddr, address(underlying), amount);
            console.log("Underlying balance: ", underlying.balanceOf(userAddr));
            underlying.approve(routerAddr, amount);
            router.provideLiquidity(userAddr, market, amount);
            console.log("FT Reserve: ", ft.balanceOf(address(market)));
            console.log("XT Reserve: ", xt.balanceOf(address(market)));
            console.log("LPFT Reserve: ", lpFt.balanceOf(userAddr));
            console.log("LPXT Reserve: ", lpXt.balanceOf(userAddr));
        }

        // // deploy router
        // address routerImpl = address(new TermMaxRouter());

        // bytes memory data = abi.encodeCall(TermMaxRouter.initialize, userAddr);
        // address proxy = address(new ERC1967Proxy(routerImpl, data));

        // TermMaxRouter router = TermMaxRouter(proxy);
        // router.togglePause(false);

        // console.log("new router address:", address(router));

        // // deploy swap adapter
        // router.setMarketWhitelist(address(market), true);
        // router.setAdapterWhitelist(address(swapAdapter), true);

        // // leverage from token
        // uint256 underlyingAmtBase = 10 ** underlying.decimals();
        // uint256 collateralAmtBase = 10 ** collateral.decimals();
        // uint256 priceBase = 1e8;
        // uint256 aprBase = 1e8;
        // uint64 daysInYear = 365;
        // uint64 secondsInDay = 86400;
        // uint64 ltvBase = 1e8;

        // config = market.config();

        // uint64 maturity = config.maturity;
        // uint64 dayToMaturity = uint64(
        //     (maturity - vm.getBlockTimestamp() + secondsInDay - 1) /
        //         secondsInDay
        // );
        // uint64 apr = config.apr > 0 ? uint64(config.apr) : uint64(-config.apr);
        // uint64 initialLtv = config.initialLtv;
        // uint256 ftPrice = (daysInYear * aprBase * priceBase) /
        //     (aprBase * daysInYear + apr * dayToMaturity);
        // uint256 xtPrice = priceBase - (ftPrice * initialLtv) / ltvBase;
        // (, int256 collateralAnswer, , , ) = collateralPriceFeed
        //     .latestRoundData();
        // (, int256 underlyingAnswer, , , ) = underlyingPriceFeed
        //     .latestRoundData();

        // uint256 collateralPrice = uint256(collateralAnswer);
        // console.log("FT APR:", apr);
        // console.log("FT price:", ftPrice);
        // console.log("XT price:", xtPrice);
        // console.log("collateral price:", collateralPrice);
        // console.log("underlying price:", underlyingAnswer);
        // console.log("day to maturity:", dayToMaturity);
        // uint256 tokenToBuyCollateralAmt = 0;
        // uint256 tokenToBuyXtAmt = 1000e6;
        // uint256 maxLtv = 89000000;
        // uint256 mintXtAmt = 0;

        // uint256 n = priceBase *
        //     collateralAmtBase *
        //     (tokenToBuyCollateralAmt *
        //         underlyingAmtBase *
        //         xtPrice +
        //         underlyingAmtBase *
        //         tokenToBuyXtAmt *
        //         priceBase);
        // uint256 d = underlyingAmtBase *
        //     underlyingAmtBase *
        //     xtPrice *
        //     collateralPrice;
        // uint256 tokenOutAmt = n / d;
        // uint256 xtAmtZeroSlippage = (tokenToBuyXtAmt * priceBase) / xtPrice;
        // SwapUnit[] memory swapUnits = new SwapUnit[](1);
        // swapUnits[0] = SwapUnit({
        //     adapter: swapAdapter,
        //     tokenIn: address(underlying),
        //     tokenOut: address(collateral),
        //     swapData: abi.encode(
        //         address(underlyingPriceFeed),
        //         address(collateralPriceFeed)
        //     )
        // });
        // console.log(
        //     "Token to buy XT amount:",
        //     tokenToBuyXtAmt / 10 ** underlying.decimals()
        // );
        // console.log("Token to buy collateral amount:", tokenToBuyCollateralAmt);
        // console.log(
        //     "Token out amount:",
        //     tokenOutAmt / 10 ** collateral.decimals()
        // );
        // underlying.mint(userAddr, tokenToBuyCollateralAmt + tokenToBuyXtAmt);
        // underlying.approve(
        //     routerAddr,
        //     tokenToBuyCollateralAmt + tokenToBuyXtAmt
        // );
        // (uint256 gtId, uint256 netXtOut) = router.leverageFromToken(
        //     userAddr,
        //     market,
        //     tokenToBuyCollateralAmt,
        //     tokenToBuyXtAmt,
        //     maxLtv,
        //     mintXtAmt,
        //     swapUnits
        // );
        // console.log("xt amount with zero slippage:", xtAmtZeroSlippage);
        // console.log("xt amount with slippage:", netXtOut);
        // (
        //     address owner,
        //     uint128 debtAmt,
        //     uint128 ltv,
        //     bytes memory collateralDta
        // ) = gt.loanInfo(gtId);
        // uint128 collateralAmt = abi.decode(collateralDta, (uint128));
        // console.log("Gearing token ID:", gtId);
        // console.log("Gearing token owner:", owner);
        // console.log(
        //     "Gearing token debt amount:",
        //     debtAmt / 10 ** underlying.decimals()
        // );
        // console.log(
        //     "Gearing token collateral amount:",
        //     collateralAmt / 10 ** collateral.decimals()
        // );
        // console.log("Gearing token ltv:", ltv);
        vm.stopBroadcast();

        // console.log("\nAfter broadcast");
        // console.log("Current timestamp:", vm.getBlockTimestamp());
        // console.log("Market open time:", config.openTime);
        // console.log("Underlying balance:", underlying.balanceOf(userAddr));
        // console.log("Underlying symbol:", underlying.symbol());
        // console.log("Collateral balance:", collateral.balanceOf(userAddr));
        // console.log("Collateral symbol:", collateral.symbol());
        // console.log("FT balance:", ft.balanceOf(userAddr));
        // console.log("XT balance:", xt.balanceOf(userAddr));
        // console.log("LPFT balance:", lpFt.balanceOf(userAddr));
        // console.log("LPXT balance:", lpXt.balanceOf(userAddr));
    }
}
