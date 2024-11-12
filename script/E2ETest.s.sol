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

contract E2ETest is Script {

    // deployer config
    uint256 userPrivateKey = vm.envUint("FORK_DEPLOYER_PRIVATE_KEY");
    address userAddr = vm.addr(userPrivateKey);
    // address userAddr = address(0x40cA1811DBfcfD3d8593B5E8Ab4a9D8a0fcB4fe8);
    // address userAddr = address(0x43155bf7Ed1393379f44df7ca7299721917e41Ef);

    // market config
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");
    MarketConfig marketConfig = MarketConfig(
        {
            treasurer: 0x944a0Af591E2C23a2E81fe4c10Bd9c47Cf866F4b,
            maturity: 1735575942, // current 1726732382
            openTime: 1726734383,
            apr: 12000000,
            lsf: 80000000,
            lendFeeRatio: 3000000,
            minNLendFeeR: 3000000,
            borrowFeeRatio: 3000000,
            minNBorrowFeeR: 3000000,
            redeemFeeRatio: 50000000,
            issueFtFeeRatio: 10000000,
            lockingPercentage: 50000000,
            initialLtv: 88000000,
            protocolFeeRatio: 50000000,
            rewardIsDistributed: true
        });
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;

    // address config
    address factoryAddr = address(0xaF29EAAEDC49C7a58F4DD5a4c074C550b2Ff63bA);
    address routerAddr = address(0x5B5b0E44A98aD498c6F5931605f0EE903E221c69);
    address marketAddr = address(0xecAcd1681F85c26D565348e03d3e1e085059Bb04);
    address collateralAddr = address(0x03AC4256dAC135Dcc088de5285b113d7219D22d7); // PT-sUSDe-24OCT2024
    address collateralOracleAddr = address(0xD752C02f557580cEC3a50a2deBF3A4C48657EeDe);
    address underlyingAddr = address(0x93CCa2C4e9e6a623046b1C6631C37DAD1299a9Ee); // USDC
    address underlyingOracleAddr = address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
    address ftAddr = address(0x79C67d5D3f63f2ABfD1d5813F7ac5f60a1Ac807a);
    address xtAddr = address(0x460751EBffA71C12BB5cbA4D409fE10B2c7A2b39);
    address lpFtAddr = address(0x871edee2836F8Cb03Ae6cf98D8A24027Dca424Be);
    address lpXtAddr = address(0xCfC4A4fF7a1F3B4728625Fbc135DcEeC404E1cf8);
    address gtAddr = address(0xFabbc298736C0d5fa9e58c9AAD61330ea912ad5e);
    
    function run() public {
        MockERC20 underlying = MockERC20(underlyingAddr);
        MockERC20 collateral = MockERC20(collateralAddr);
        IERC20 ft = IERC20(ftAddr);
        IERC20 xt = IERC20(xtAddr);
        IERC20 lpFt = IERC20(lpFtAddr);
        IERC20 lpXt = IERC20(lpXtAddr);
        IGearingToken gt = IGearingToken(gtAddr);
        ITermMaxRouter router = ITermMaxRouter(routerAddr);
        ITermMaxMarket market = ITermMaxMarket(marketAddr);
        MarketConfig memory config = market.config();
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

        underlying.mint(userAddr, 1000000000);
        vm.startBroadcast(userPrivateKey);
        // underlying.approve(marketAddr, 1000000000);
        // market.provideLiquidity(100000000);
        underlying.approve(routerAddr, 1000000000);
        router.provideLiquidity(userAddr, market, 100000000);
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
