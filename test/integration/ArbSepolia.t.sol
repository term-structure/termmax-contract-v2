// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../../../contracts/core/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../../contracts/core/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../../../contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "../../../contracts/router/ITermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../../../contracts/core/TermMaxMarket.sol";
import {ITermMaxMarket} from "../../../contracts/core/TermMaxMarket.sol";
import {MockERC20} from "../../../contracts/test/MockERC20.sol";
import {MarketConfig} from "../../../contracts/core/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../../../contracts/core/tokens/IMintableERC20.sol";
import {IGearingToken, AggregatorV3Interface} from "../../../contracts/core/tokens/IGearingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../../../contracts/test/MockSwapAdapter.sol";
import {Faucet} from "../../../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../../../contracts/test/testnet/FaucetERC20.sol";
import {SwapUnit} from "../../../contracts/router/ISwapAdapter.sol";

contract E2ETest is Test {
    // deployer config
    uint256 userPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address userAddr = vm.addr(userPrivateKey);

    // address config
    address faucetAddr = address(0x0432797D126A0d8c3cb5038b4b4184eEDB3CD4f5);
    address factoryAddr = address(0xa55812c99cF244eDe28BB700d40dDd912646B06e);
    address routerAddr = address(0x1864966FED6A7De651400a48B2d677b88ac26545);
    address swapAdapter = address(0xCDE68b00200d4A54A997a05f711F6882E738787A);
    address marketAddr = address(0x5eB5d2Ac2E4aB3E8b0Af6d836947535BB32A1d59);

    TermMaxMarket market = TermMaxMarket(marketAddr);
    TermMaxRouter router = TermMaxRouter(routerAddr);
    IMintableERC20 ft;
    IMintableERC20 xt;
    IMintableERC20 lpFt;
    IMintableERC20 lpXt;
    IGearingToken gt;
    address collateralAddr;
    FaucetERC20 collateral;
    FaucetERC20 underlying;
    IERC20 underlyingERC20;

    function setUp() public {
        string memory ARB_SEPOLIA_RPC_URL = vm.envString("ARB_SEPOLIA_RPC_URL");
        uint256 arbSepoliaFork = vm.createFork(ARB_SEPOLIA_RPC_URL);
        vm.selectFork(arbSepoliaFork);
        vm.rollFork(100850534);
        vm.warp(1732648114);

        MarketConfig memory config = market.config();
        (ft, xt, lpFt, lpXt, gt, collateralAddr, underlyingERC20) = market
            .tokens();
        collateral = FaucetERC20(collateralAddr);
        underlying = FaucetERC20(address(underlyingERC20));
    }

    function testIntegration() public {
        // provide liquidity
        vm.startBroadcast(userPrivateKey);
        uint256 amount = 1000000e6;
        underlying.mint(userAddr, amount);
        underlying.approve(routerAddr, amount);
        router.provideLiquidity(userAddr, market, amount);
        vm.stopBroadcast();

        // leverage from token
        vm.startBroadcast(userPrivateKey);
        uint256 tokenInAmt = 1000000000;
        uint256 tokenToBuyXtAmt = 100000000;
        uint256 maxLtv = 89000000;
        uint256 mintXtAmt = 0;
        uint256 tokenOutAmt = ((tokenInAmt + tokenToBuyXtAmt * 10) * 10e18) /
            10e6;
        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: swapAdapter,
            tokenIn: address(underlying),
            tokenOut: address(collateral),
            swapData: abi.encode(tokenOutAmt)
        });
        underlying.mint(userAddr, tokenInAmt + tokenToBuyXtAmt);
        underlying.approve(routerAddr, tokenInAmt + tokenToBuyXtAmt);
        (uint256 gtId, uint256 netXtOut) = router.leverageFromToken(
            userAddr,
            market,
            tokenInAmt,
            tokenToBuyXtAmt,
            maxLtv,
            mintXtAmt,
            swapUnits
        );
        (
            address owner,
            uint128 debtAmt,
            uint128 ltv,
            bytes memory collateralDta
        ) = gt.loanInfo(gtId);
        uint128 collateralAmt = abi.decode(collateralDta, (uint128));
        console.log("Gearing token ID:", gtId);
        console.log("Gearing token owner:", owner);
        console.log("Gearing token debt amount:", debtAmt);
        console.log("Gearing token collateral amount:", collateralAmt);
        console.log("Gearing token ltv:", ltv);
        vm.stopBroadcast();
    }
}
