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
    MarketConfig marketConfig =
        MarketConfig({
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
    address factoryAddr = address(0x715F4a22c4F4224BFDDB64B980a7363c505015bF);
    address routerAddr = address(0xDbD9F1346979A7E9c4e9dB326566577349a84CcF);
    address marketAddr = address(0xD78014C3A86017748a2e831Bc2DCA3eAF9f17764);
    address collateralAddr =
        address(0x3E2628096FE52b255aF0Ce6973B90C9e6A5c808e); // PT-sUSDe-24OCT2024
    address collateralOracleAddr =
        address(0xD752C02f557580cEC3a50a2deBF3A4C48657EeDe);
    address underlyingAddr =
        address(0xbcc27BB9eF1C6AC82E1D39874A96C813099aF747); // USDC
    address underlyingOracleAddr =
        address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
    address ftAddr = address(0x84b006c8092699A2295Afa8e47C05B865ebE9fdD);
    address xtAddr = address(0xfBCB0465a83F525411c681C5839B583C1FD96Ad1);
    address lpFtAddr = address(0x4c19C73ce1cc621387D75FbE45F071aaAF1013E9);
    address lpXtAddr = address(0xe997f16D4aC9278545F5CBeCff9CBc14923b6506);
    address gtAddr = address(0x309155273D07Cc7a5738ca752503b830EfFde64e);

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
        uint256 amount = 1000e6;
        underlying.mint(userAddr, amount);
        underlying.approve(routerAddr, amount);
        router.provideLiquidity(userAddr, market, amount);
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
