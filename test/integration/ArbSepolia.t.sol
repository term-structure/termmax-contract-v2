// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../../contracts/core/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../contracts/core/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../../contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "../../contracts/router/ITermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../../contracts/core/TermMaxMarket.sol";
import {ITermMaxMarket} from "../../contracts/core/TermMaxMarket.sol";
import {MockERC20} from "../../contracts/test/MockERC20.sol";
import {MarketConfig} from "../../contracts/core/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../../contracts/core/tokens/IMintableERC20.sol";
import {IGearingToken} from "../../contracts/core/tokens/IGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../../contracts/test/MockSwapAdapter.sol";
import {Faucet} from "../../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../../contracts/test/testnet/FaucetERC20.sol";
import {SwapUnit} from "../../contracts/router/ISwapAdapter.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";

contract E2ETest is Test {
    // deployer config
    uint256 userPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address userAddr = vm.addr(userPrivateKey);

    // address config
    // address faucetAddr = address(0xdB94B6E81E0b9F0874ABa5F4F8258c31A9b97Ce8);
    // address factoryAddr = address(0x4f29f479D3e6c41aD3fC8C7c8D6f423Cb2784b8e);
    address routerAddr = address(0xA53500974648F3d00336a0533955e3404503dB90);
    address swapAdapter = address(0x98838B33E85A56b2C9c8F7D7D6a1A7d2484b8e67);
    address marketAddr = address(0x78494Cbb1AB24900f045b673e6640eb0595aD2D7);
    address collateralPriceFeedAddr =
        address(0x1Aee5396e5B010Eb6462396c4D8753B66B0ae089);
    address underlyingPriceFeedAddr =
        address(0x6f2c71259f2935c106769bEBc3A6a6ED86533616);

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
    MockPriceFeed collateralPriceFeed = MockPriceFeed(collateralPriceFeedAddr);
    MockPriceFeed underlyingPriceFeed =
        MockPriceFeed(address(underlyingPriceFeedAddr));

    function setUp() public {
        string memory ARB_SEPOLIA_RPC_URL = vm.envString("ARB_SEPOLIA_RPC_URL");
        // string memory ARB_SEPOLIA_RPC_URL = "http://127.0.0.1:8545";

        uint256 arbSepoliaFork = vm.createFork(ARB_SEPOLIA_RPC_URL);
        vm.selectFork(arbSepoliaFork);
        vm.rollFork(101029414);
        // vm.warp(1732648114);
        vm.warp(vm.getBlockTimestamp() + 100);

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
        uint256 underlyingAmtBase = 10 ** underlying.decimals();
        uint256 collateralAmtBase = 10 ** collateral.decimals();
        uint256 priceBase = 1e8;
        uint256 aprBase = 1e8;
        uint64 daysInYear = 365;
        uint64 secondsInDay = 86400;
        uint64 ltvBase = 1e8;

        MarketConfig memory config = market.config();
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
                underlyingPriceFeedAddr,
                collateralPriceFeedAddr
            )
        });
        console.log(
            "Token to buy XT amount:",
            tokenToBuyXtAmt / 10 ** underlying.decimals()
        );
        console.log("Token to buy collateral amount:", tokenToBuyCollateralAmt);
        console.log("xt amount with zero slippage:", xtAmtZeroSlippage);
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
            swapUnits,
            config.lsf
        );
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
    }
}
