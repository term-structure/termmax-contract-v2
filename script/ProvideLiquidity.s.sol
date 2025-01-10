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
import {IGearingToken} from "../contracts/core/tokens/IGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../contracts/test/MockSwapAdapter.sol";
import {Faucet} from "../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../contracts/test/testnet/FaucetERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {SwapUnit} from "../contracts/router/ISwapAdapter.sol";
import {MarketConfig} from "../contracts/core/storage/TermMaxStorage.sol";

contract ProvideLiquidity is Script {
    // deployer config
    uint256 userPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address userAddr = vm.addr(userPrivateKey);

    // address config
    address faucetAddr = address(0xd0dcc724070D7F72E8F7f2E0E4cDE5a5A3006aDB);
    address routerAddr = address(0xE080d1B17A67F96F865143269Dc991cDDB01D996);
    address[] markets = [
        address(0x90B86eAD2C95f1BC37c191CC7f1e67Eb63A25A34),
        address(0xe7E731da17D5635D663f63B65b200d4FCed39FAa),
        address(0x09DD5F4F3C67b4936D66F869Cc0306d866D8DB46),
        address(0xB15D4e2e774DeaD70ceC268dbB6E836250a19acf),
        address(0x007938e8b17c37C4B250510ab9f97e90ae978A9C),
        address(0xaeDac43bF468583AD93F04BB0AeF0428BB2FC1C5)
    ];
    uint256 initialLiquidityAmt = 20000000;

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
        // provide liquidity
        for (uint i = 0; i < markets.length; i++) {
            address marketAddr = markets[i];
            market = TermMaxMarket(marketAddr);
            config = market.config();
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
            (, int256 ans, , , ) = underlyingPriceFeed.latestRoundData();
            uint256 underlyingPrice = uint256(ans);
            uint256 priceDecimalBase = 10 ** underlyingPriceFeed.decimals();
            uint256 amount = ((initialLiquidityAmt *
                priceDecimalBase *
                10 ** underlying.decimals()) / underlyingPrice);
            faucet.devMint(userAddr, address(underlying), amount);
            underlying.approve(routerAddr, amount);
            router.provideLiquidity(userAddr, market, amount);
            console.log("Market address", marketAddr);
            console.log("FT Reserve: ", ft.balanceOf(address(market)));
            console.log("XT Reserve: ", xt.balanceOf(address(market)));
        }
        vm.stopBroadcast();
    }
}
