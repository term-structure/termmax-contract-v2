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

contract E2ETest is Script {
    // deployer config
    uint256 userPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address userAddr = vm.addr(userPrivateKey);

    // address config
    address factoryAddr = address(0x65feE48150586e72038884920b92033746f324b0);
    address routerAddr = address(0x07c20177b6F219367F32fE72D8A70aA299920A8F);
    address marketAddr = address(0x806fdCb526E084b97541b9e65EaEF60DfF04be95);
    address collateralAddr =
        address(0xcd3379a8b94FaA5F117A3e97c5f244504788cc25);
    address underlyingAddr =
        address(0x791124EE95C885cdccD1A4ec62AB328ce1472a36);

    // address underlyingOracleAddr =
    //     address(0x8BAdE2BBb4AB2533800E22acd8ba2D34DE49acE6);
    // address collateralOracleAddr =
    //     address(0x8Ddbc0a49B8f93066535f2c683cD5a8e83826151);

    address ftAddr = address(0x76ee69AB1e720704ca8F0CEe6e92ac8Cc8Fa0c9F);
    address xtAddr = address(0x00bdc53aC57d27EB509255a465623416a143ffCF);
    address lpFtAddr = address(0x1Ea586b735e2e98d3B88d290DdfA275f3aCCc5ff);
    address lpXtAddr = address(0x7eaA9Cd362E45D787B326Aad77E24f81c7298c87);
    address gtAddr = address(0xD9664F0BC5E371408ed8F8B27913497bb5a26B25);

    function run() public {
        MockERC20 underlying = MockERC20(underlyingAddr);
        MockERC20 collateral = MockERC20(collateralAddr);
        ITermMaxRouter router = ITermMaxRouter(routerAddr);
        ITermMaxMarket market = ITermMaxMarket(marketAddr);
        IERC20 ft = IERC20(ftAddr);
        IERC20 xt = IERC20(xtAddr);
        IERC20 lpFt = IERC20(lpFtAddr);
        IERC20 lpXt = IERC20(lpXtAddr);
        IGearingToken gt = IGearingToken(gtAddr);

        MarketConfig memory config = market.config();
        (, , , , , address collateralM, IERC20 underlyingM) = market.tokens();
        console.log("user address:", userAddr);
        console.log("market underlying:", address(underlyingM));
        console.log("market collateral:", collateralM);
        console.log("Before broadcast");
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

        vm.startBroadcast(userPrivateKey);
        uint256 amount = 1000000e6;
        underlying.mint(userAddr, amount);
        underlying.approve(routerAddr, amount);
        router.provideLiquidity(userAddr, market, amount);
        // address pool = vm.randomAddress();
        // MockSwapAdapter swapAdapter = new MockSwapAdapter(pool);
        // router.setAdapterWhitelist(address(swapAdapter), true);
        // console.log("Swap adapter address:", address(swapAdapter));
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
