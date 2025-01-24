// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "../contracts/router/ITermMaxRouter.sol";
import {TermMaxOrder} from "../contracts/TermMaxOrder.sol";
import {ITermMaxOrder} from "../contracts/TermMaxOrder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket, Constants} from "../contracts/TermMaxMarket.sol";
import {ITermMaxMarket} from "../contracts/TermMaxMarket.sol";
import {MockERC20} from "../contracts/test/MockERC20.sol";
import {MarketConfig} from "../contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../contracts/tokens/IMintableERC20.sol";
import {IGearingToken} from "../contracts/tokens/IGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../contracts/test/MockSwapAdapter.sol";
import {Faucet} from "../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../contracts/test/testnet/FaucetERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {SwapUnit} from "../contracts/router/ISwapAdapter.sol";
import {MarketConfig} from "../contracts/storage/TermMaxStorage.sol";

contract E2ETest is Script {
    // deployer config
    uint256 userPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address userAddr = vm.addr(userPrivateKey);

    // address config
    address faucetAddr = address(0x422738015AF2E812D5Ec73BdE20bE06755508696);
    address routerAddr = address(0xA44742D456e644D4108B8B4421189EF46F583812);
    address swapAdapter = address(0x65feE48150586e72038884920b92033746f324b0);
    address marketAddr = address(0x0D5168Ae17e62B42ed85DD8Cc35DA7913Ec41dd6);
    address orderAddr = address(0x20fC1552744D7726827D69248c6cB9733A70FA1C);

    Faucet faucet = Faucet(faucetAddr);
    TermMaxRouter router = TermMaxRouter(routerAddr);
    TermMaxMarket market = TermMaxMarket(marketAddr);
    TermMaxOrder order = TermMaxOrder(orderAddr);
    IMintableERC20 ft;
    IMintableERC20 xt;
    IGearingToken gt;
    address collateralAddr;
    IERC20 underlyingERC20;
    FaucetERC20 collateral;
    FaucetERC20 underlying;
    address collateralPriceFeedAddr;
    address underlyingPriceFeedAddr;

    function run() public {
        (ft, xt, gt, collateralAddr, underlyingERC20) = market.tokens();
        collateral = FaucetERC20(collateralAddr);
        underlying = FaucetERC20(address(underlyingERC20));
        underlyingPriceFeedAddr = faucet.getTokenConfig(faucet.getTokenId(address(underlying))).priceFeedAddr;
        collateralPriceFeedAddr = faucet.getTokenConfig(faucet.getTokenId(address(collateral))).priceFeedAddr;
        printMarketConfig();
        depositIntoOrder(100000);
        lendToOrder(1);
        borrowFromOrder(12000, 8000, 8500);
        leverageFromOrder(4e6, 0, 20000e6, 0.8e8);
    }

    function depositIntoOrder(uint256 depositAmt) public {
        vm.startBroadcast(userPrivateKey);
        depositAmt = depositAmt * 10 ** underlying.decimals();
        faucet.devMint(userAddr, address(underlying), depositAmt);
        (uint256 oriFtReserve, uint256 oriXtReserve) = order.tokenReserves();

        underlying.approve(address(market), depositAmt);
        market.mint(address(order), depositAmt);
        (uint256 newFtReserve, uint256 newXtReserve) = order.tokenReserves();
        (uint256 newLendApr, uint256 newBorrowApr) = order.apr();
        console.log("");
        vm.stopBroadcast();
        console.log("--- Deposit into order ---");
        console.log("ori ftReserve:", oriFtReserve);
        console.log("ori xtReserve:", oriXtReserve);
        console.log("new ftReserve:", newFtReserve);
        console.log("new xtReserve:", newXtReserve);
        console.log("new lendApr:", newLendApr);
        console.log("new borrowApr:", newBorrowApr);
    }

    function lendToOrder(uint256 lendAmt) public {
        (uint256 oriFtReserve, uint256 oriXtReserve) = order.tokenReserves();
        (uint256 oriLendApr, uint256 oriBorrowApr) = order.apr();
        uint256 oriFtBalance = ft.balanceOf(userAddr);

        vm.startBroadcast(userPrivateKey);
        lendAmt = lendAmt * 10 ** underlying.decimals();
        faucet.devMint(userAddr, address(underlying), lendAmt);
        uint256 oriUnderlyingBalance = underlying.balanceOf(userAddr);
        underlying.approve(address(order), lendAmt);
        order.swapExactTokenToToken(underlying, ft, userAddr, uint128(lendAmt), 0);
        vm.stopBroadcast();

        (uint256 newFtReserve, uint256 newXtReserve) = order.tokenReserves();
        (uint256 newLendApr, uint256 newBorrowApr) = order.apr();
        uint256 newUnderlyingBalance = underlying.balanceOf(userAddr);
        uint256 newFtBalance = ft.balanceOf(userAddr);

        console.log("--- Lend to order ---");
        console.log("ori ftReserve:", oriFtReserve);
        console.log("ori xtReserve:", oriXtReserve);
        console.log("ori lendApr:", oriLendApr);
        console.log("ori borrowApr:", oriBorrowApr);
        console.log("ori underlyingBalance:", oriUnderlyingBalance);
        console.log("ori ftBalance:", oriFtBalance);
        console.log("new ftReserve:", newFtReserve);
        console.log("new xtReserve:", newXtReserve);
        console.log("new lendApr:", newLendApr);
        console.log("new borrowApr:", newBorrowApr);
        console.log("new underlyingBalance:", newUnderlyingBalance);
        console.log("new ftBalance:", newFtBalance);
    }

    function borrowFromOrder(uint256 collateralAmt, uint256 borrowAmt, uint256 maxDebtAmt) public {
        collateralAmt = collateralAmt * 10 ** collateral.decimals();
        borrowAmt = borrowAmt * 10 ** underlying.decimals();
        maxDebtAmt = maxDebtAmt * 10 ** underlying.decimals();
        (uint256 oriFtReserve, uint256 oriXtReserve) = order.tokenReserves();
        (uint256 oriLendApr, uint256 oriBorrowApr) = order.apr();
        uint256 oriUnderlyingBalance = underlying.balanceOf(userAddr);

        vm.startBroadcast(userPrivateKey);
        faucet.devMint(userAddr, collateralAddr, collateralAmt);
        uint256 oriCollateralBalance = collateral.balanceOf(userAddr);
        uint256 fee = (market.issueFtFeeRatio() * maxDebtAmt) / Constants.DECIMAL_BASE;
        uint256 ftAmt = maxDebtAmt - fee;
        collateral.approve(address(router), collateralAmt);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = order;
        uint128[] memory ftAmtsToSell = new uint128[](1);
        ftAmtsToSell[0] = uint128(borrowAmt);
        router.borrowTokenFromCollateral(userAddr, market, collateralAmt, orders, ftAmtsToSell, uint128(maxDebtAmt));
        vm.stopBroadcast();

        (uint256 newFtReserve, uint256 newXtReserve) = order.tokenReserves();
        (uint256 newLendApr, uint256 newBorrowApr) = order.apr();
        uint256 newUnderlyingBalance = underlying.balanceOf(userAddr);
        uint256 newCollateralBalance = collateral.balanceOf(userAddr);

        console.log("--- Borrow from order ---");
        console.log("ori ftReserve:", oriFtReserve);
        console.log("ori xtReserve:", oriXtReserve);
        console.log("ori lendApr:", oriLendApr);
        console.log("ori borrowApr:", oriBorrowApr);
        console.log("ori underlyingBalance:", oriUnderlyingBalance);
        console.log("ori collateralBalance:", oriCollateralBalance);
        console.log("new ftReserve:", newFtReserve);
        console.log("new xtReserve:", newXtReserve);
        console.log("new lendApr:", newLendApr);
        console.log("new borrowApr:", newBorrowApr);
        console.log("new underlyingBalance:", newUnderlyingBalance);
        console.log("new collateralBalance:", newCollateralBalance);
    }

    function leverageFromOrder(uint128 amtToBuyXt, uint128 minXtOut, uint128 tokenToSwap, uint128 maxLtv) public {
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = order;
        uint128[] memory amtsToBuyXt = new uint128[](1);
        amtsToBuyXt[0] = amtToBuyXt;
        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(
            address(swapAdapter),
            address(underlying),
            address(collateral),
            abi.encode(underlyingPriceFeedAddr, collateralPriceFeedAddr)
        );

        (uint256 oriFtReserve, uint256 oriXtReserve) = order.tokenReserves();
        (uint256 oriLendApr, uint256 oriBorrowApr) = order.apr();
        uint256 oriUnderlyingBalance = underlying.balanceOf(userAddr);

        vm.startBroadcast(userPrivateKey);
        faucet.devMint(address(userAddr), address(underlying), amtToBuyXt + tokenToSwap);
        underlying.approve(address(router), amtToBuyXt + tokenToSwap);
        router.leverageFromToken(userAddr, market, orders, amtsToBuyXt, minXtOut, tokenToSwap, maxLtv, units);
        vm.stopBroadcast();

        (uint256 newFtReserve, uint256 newXtReserve) = order.tokenReserves();
        (uint256 newLendApr, uint256 newBorrowApr) = order.apr();
        uint256 newUnderlyingBalance = underlying.balanceOf(userAddr);
        uint256 newCollateralBalance = collateral.balanceOf(userAddr);

        console.log("--- Leverage from order ---");
        console.log("ori ftReserve:", oriFtReserve);
        console.log("ori xtReserve:", oriXtReserve);
        console.log("ori lendApr:", oriLendApr);
        console.log("ori borrowApr:", oriBorrowApr);
        console.log("ori underlyingBalance:", oriUnderlyingBalance);
        console.log("new ftReserve:", newFtReserve);
        console.log("new xtReserve:", newXtReserve);
        console.log("new lendApr:", newLendApr);
        console.log("new borrowApr:", newBorrowApr);
        console.log("new underlyingBalance:", newUnderlyingBalance);
    }

    function printMarketConfig() public view {
        MarketConfig memory config = market.config();
        console.log("--- Market Config ---");
        console.log("Treasurer:", config.treasurer);
        console.log("Maturity:", config.maturity);
        console.log("lendTakerFeeRatio:", config.feeConfig.lendTakerFeeRatio);
        console.log("lendMakerFeeRatio:", config.feeConfig.lendMakerFeeRatio);
        console.log("borrowTakerFeeRatio:", config.feeConfig.borrowTakerFeeRatio);
        console.log("borrowMakerFeeRatio:", config.feeConfig.borrowMakerFeeRatio);
        console.log("issueFtFeeRatio:", config.feeConfig.issueFtFeeRatio);
        console.log("issueFtFeeRef:", config.feeConfig.issueFtFeeRef);
        console.log("redeemFeeRatio:", config.feeConfig.redeemFeeRatio);
        console.log("");
    }
}
