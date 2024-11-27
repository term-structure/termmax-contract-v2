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
    address faucetAddr = address(0x12A9F6A4F06F7EF2595B4DEEa3C05f80F8C38c2a);
    address routerAddr = address(0x6280790db5007241e6C5Cb76AA8c367C13b98DC9);
    address swapAdapter = address(0x832B66EFA6578c4fAceE88ADC9d1F42F39E4B3D8);
    address marketAddr = address(0x73A5E4807F63C50d28113777C3d34CB40d2F6EE2);

    TermMaxMarket market;
    TermMaxRouter router;
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
        Faucet faucet = Faucet(faucetAddr);
        router = TermMaxRouter(routerAddr);
        market = TermMaxMarket(marketAddr);
        (ft, xt, lpFt, lpXt, gt, collateralAddr, underlyingERC20) = market
            .tokens();
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

        vm.startBroadcast(userPrivateKey);
        // provide liquidity
        uint256 amount = 1000000e6;
        faucet.devMint(userAddr, address(underlying), amount);
        underlying.approve(routerAddr, amount);
        router.provideLiquidity(userAddr, market, amount);

        // leverage from token
        uint256 underlyingAmtBase = 10 ** underlying.decimals();
        uint256 collateralAmtBase = 10 ** collateral.decimals();
        uint256 priceBase = 1e8;
        uint256 aprBase = 1e8;
        uint64 daysInYear = 365;
        uint64 secondsInDay = 86400;
        uint64 ltvBase = 1e8;

        config = market.config();

        uint64 maturity = config.maturity;
        uint64 dayToMaturity = uint64(
            (maturity - vm.getBlockTimestamp() + secondsInDay - 1) /
                secondsInDay
        );
        uint64 apr = config.apr > 0 ? uint64(config.apr) : uint64(-config.apr);
        uint64 initialLtv = config.initialLtv;
        uint256 ftPrice = (daysInYear * aprBase * priceBase) /
            (aprBase * daysInYear + apr * dayToMaturity);
        uint256 xtPrice = priceBase - (ftPrice * initialLtv) / ltvBase;
        (, int256 collateralAnswer, , , ) = collateralPriceFeed
            .latestRoundData();
        (, int256 underlyingAnswer, , , ) = underlyingPriceFeed
            .latestRoundData();

        uint256 collateralPrice = uint256(collateralAnswer);
        console.log("FT APR:", apr);
        console.log("FT price:", ftPrice);
        console.log("XT price:", xtPrice);
        console.log("collateral price:", collateralPrice);
        console.log("underlying price:", underlyingAnswer);
        console.log("day to maturity:", dayToMaturity);
        uint256 tokenToBuyCollateralAmt = 0;
        uint256 tokenToBuyXtAmt = 1000e6;
        uint256 maxLtv = 89000000;
        uint256 mintXtAmt = 0;

        uint256 n = priceBase *
            collateralAmtBase *
            (tokenToBuyCollateralAmt *
                underlyingAmtBase *
                xtPrice +
                underlyingAmtBase *
                tokenToBuyXtAmt *
                priceBase);
        uint256 d = underlyingAmtBase *
            underlyingAmtBase *
            xtPrice *
            collateralPrice;
        uint256 tokenOutAmt = n / d;
        uint256 xtAmtZeroSlippage = (tokenToBuyXtAmt * priceBase) / xtPrice;
        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: swapAdapter,
            tokenIn: address(underlying),
            tokenOut: address(collateral),
            swapData: abi.encode(
                address(underlyingPriceFeed),
                address(collateralPriceFeed)
            )
        });
        console.log(
            "Token to buy XT amount:",
            tokenToBuyXtAmt / 10 ** underlying.decimals()
        );
        console.log("Token to buy collateral amount:", tokenToBuyCollateralAmt);
        console.log(
            "Token out amount:",
            tokenOutAmt / 10 ** collateral.decimals()
        );
        underlying.mint(userAddr, tokenToBuyCollateralAmt + tokenToBuyXtAmt);
        underlying.approve(
            routerAddr,
            tokenToBuyCollateralAmt + tokenToBuyXtAmt
        );
        (uint256 gtId, uint256 netXtOut) = router.leverageFromToken(
            userAddr,
            market,
            tokenToBuyCollateralAmt,
            tokenToBuyXtAmt,
            maxLtv,
            mintXtAmt,
            swapUnits
        );
        console.log("xt amount with zero slippage:", xtAmtZeroSlippage);
        console.log("xt amount with slippage:", netXtOut);
        (
            address owner,
            uint128 debtAmt,
            uint128 ltv,
            bytes memory collateralDta
        ) = gt.loanInfo(gtId);
        uint128 collateralAmt = abi.decode(collateralDta, (uint128));
        console.log("Gearing token ID:", gtId);
        console.log("Gearing token owner:", owner);
        console.log(
            "Gearing token debt amount:",
            debtAmt / 10 ** underlying.decimals()
        );
        console.log(
            "Gearing token collateral amount:",
            collateralAmt / 10 ** collateral.decimals()
        );
        console.log("Gearing token ltv:", ltv);
        vm.stopBroadcast();

        console.log("\nAfter broadcast");
        console.log("Current timestamp:", vm.getBlockTimestamp());
        console.log("Market open time:", config.openTime);
        console.log("Underlying balance:", underlying.balanceOf(userAddr));
        console.log("Underlying symbol:", underlying.symbol());
        console.log("Collateral balance:", collateral.balanceOf(userAddr));
        console.log("Collateral symbol:", collateral.symbol());
        console.log("FT balance:", ft.balanceOf(userAddr));
        console.log("XT balance:", xt.balanceOf(userAddr));
        console.log("LPFT balance:", lpFt.balanceOf(userAddr));
        console.log("LPXT balance:", lpXt.balanceOf(userAddr));
    }
}
