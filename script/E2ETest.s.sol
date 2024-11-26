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

contract E2ETest is Script {
    // deployer config
    uint256 userPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address userAddr = vm.addr(userPrivateKey);

    // address config
    address faucetAddr = address(0xf3E27621f6b13d8f4431FbB9C72273143D5Bd60d);
    address factoryAddr = address(0x4f46c989EE4611352212784b56bc41E2431488a7);
    address routerAddr = address(0xe7f3Eb4113b2f70Db591596A2dd27a797fc2fe48);
    address swapAdapter = address(0x26D109174e9367BE59751a0d32A4Db2cA8243A60);
    address marketAddr = address(0x0fFE9Aa7321dc63a3dC063591C314157FbAC4a52);
    address collateralAddr =
        address(0x8A5673EfCc8d7bBC9C22d0A9282b3320393Af6F9);
    address underlyingAddr =
        address(0x85E99c1619f941c7B2827550B58d5d8f6B0ae738);
    address ftAddr = address(0xEFB17e72Df8FbC0E0585b839F0cD676a5a2ad91d);
    address xtAddr = address(0x4310625D02526f4acE1FD25Db8ec6ddda0e5fAc4);
    address lpFtAddr = address(0x6c1590364ca5D002CEaBC4724630441c4Ddd1710);
    address lpXtAddr = address(0x9e509E576A1367F3315bC162C0e640Ae8962c978);
    address gtAddr = address(0x795A621B83B008D89C39c8aBeF9c7042dC1052Dc);

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
        Faucet faucet = Faucet(faucetAddr);

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
        Faucet.TokenConfig memory usdcConfig = faucet.getTokenConfig(1);
        uint256 amount = 1000000e6;
        faucet.devMint(userAddr, usdcConfig.tokenAddr, amount);
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
