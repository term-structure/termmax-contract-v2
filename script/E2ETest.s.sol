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
    uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address userAddr = deployerAddr;
    uint256 userPrivateKey = deployerPrivateKey;

    // address config
    address faucetAddr = address(0xb927B74d5D9c3985D4DCdd62CbffEc66CF527fAa);
    address routerAddr = address(0x04bab94F939654E3711778c25683bBB34bC1a514);
    address swapAdapter = address(0xC622E39c594570c731baCcDc2b6cD062EF941b06);
    address marketAddr = address(0x10d9baa4A6475ee2b913755728342c7d40ce0A21);
    address orderAddr = address(0x550a95c76A929635E7836cBef401C378485f4422);

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
        // list these token address in an array and remove the redundent ones
        // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        // 0xD9A442856C234a39a81a089C06451EBAa4306a72
        // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        // 0xC4441c2BE5d8fA8126822B9929CA0b81Ea0DE38E
        // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        address[] memory tokens = new address[](8);
        tokens[0] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        tokens[1] = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        tokens[2] = address(0xD9A442856C234a39a81a089C06451EBAa4306a72);
        tokens[3] = address(0xC4441c2BE5d8fA8126822B9929CA0b81Ea0DE38E);
        tokens[4] = address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
        tokens[5] = address(0x90D2af7d622ca3141efA4d8f1F24d86E5974Cc8F);
        tokens[6] = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
        tokens[7] = address(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);
        address[] memory priceFeeds = new address[](8);
        priceFeeds[0] = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        priceFeeds[1] = address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        priceFeeds[2] = address(0xDe3f7Dd92C4701BCf59F47235bCb61e727c45f80);
        priceFeeds[3] = address(0x2240AE461B34CC56D654ba5FA5830A243Ca54840);
        priceFeeds[4] = address(0xFF3BC18cCBd5999CE63E788A1c250a88626aD099);
        priceFeeds[5] = address(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
        priceFeeds[6] = address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        priceFeeds[7] = address(0x2665701293fCbEB223D11A08D826563EDcCE423A);

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Metadata token = IERC20Metadata(tokens[i]);
            AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[i]);
            (, int256 price,,,) = priceFeed.latestRoundData();
            console.log("Token address:", tokens[i]);
            console.log("Token name:", token.name());
            console.log("Token symbol:", token.symbol());
            console.log("Token decimals:", token.decimals());
            console.log("Price Feed address:", priceFeeds[i]);
            console.log("Price Feed:", price);
            console.log("");
        }
        // (userAddr, userPrivateKey) = makeAddrAndKey("New User1");
        // vm.startBroadcast(deployerPrivateKey);
        // payable(userAddr).transfer(0.1 ether);
        // vm.stopBroadcast();
        // (ft, xt, gt, collateralAddr, underlyingERC20) = market.tokens();
        // collateral = FaucetERC20(collateralAddr);
        // underlying = FaucetERC20(address(underlyingERC20));
        // underlyingPriceFeedAddr = faucet.getTokenConfig(faucet.getTokenId(address(underlying))).priceFeedAddr;
        // collateralPriceFeedAddr = faucet.getTokenConfig(faucet.getTokenId(address(collateral))).priceFeedAddr;
        // printMarketConfig();
        // mintDebtToken(deployerAddr, 100000);
        // depositIntoOrder(100000);
        // printUserPosition();

        // console.log('> Mint 21504 debt token');
        // mintDebtToken(userAddr, 21504);
        // printUserPosition();

        // console.log('> Mint 12100 collateral token');
        // mintCollateralToken(userAddr, 12100);
        // printUserPosition();
        // console.log('> Buy FT with 1000 debt token');
        // lendToOrder(1000);
        // printUserPosition();

        // console.log('> Borrow  8000 debt token with 12000 coll collateral token');
        // uint256 gtId = borrowFromOrder(12000, 8000, 8500);
        // printUserPosition();

        // console.log('> Add 100 collateral');
        // addCollateral(gtId, 100);
        // printUserPosition();

        // console.log('> Remove 50 collateral');
        // removeCollateral(gtId, 50);
        // printUserPosition();

        // console.log('> Repay 500 debt token');
        // repay(gtId, 500, true);
        // printUserPosition();

        // address to = vm.randomAddress();
        // console.log('> Transfer GT to', to);
        // transferGT(gtId, to);
        // printUserPosition();

        // console.log('> Buy XT with 4 debt token and do leverage with 20000 debt token');
        // leverageFromOrder(4, 0, 20000, 0.8e8);
        // printUserPosition();
    }

    function mintDebtToken(address to, uint256 amount) public {
        uint256 mintAmt = amount * 10 ** underlying.decimals();
        vm.startBroadcast(deployerPrivateKey);
        faucet.devMint(to, address(underlying), mintAmt);
        vm.stopBroadcast();
    }

    function mintCollateralToken(address to, uint256 amount) public {
        uint256 mintAmt = amount * 10 ** collateral.decimals();
        vm.startBroadcast(deployerPrivateKey);
        faucet.devMint(to, address(collateral), mintAmt);
        vm.stopBroadcast();
    }

    function depositIntoOrder(uint256 depositAmt) public {
        vm.startBroadcast(deployerPrivateKey);
        depositAmt = depositAmt * 10 ** underlying.decimals();
        (uint256 oriFtReserve, uint256 oriXtReserve) = order.tokenReserves();

        underlying.approve(address(market), depositAmt);
        market.mint(address(order), depositAmt);
        (uint256 newFtReserve, uint256 newXtReserve) = order.tokenReserves();
        (uint256 newLendApr, uint256 newBorrowApr) = order.apr();
        console.log("");
        vm.stopBroadcast();
        // console.log("--- Deposit into order ---");
        // console.log("ori ftReserve:", oriFtReserve);
        // console.log("ori xtReserve:", oriXtReserve);
        // console.log("new ftReserve:", newFtReserve);
        // console.log("new xtReserve:", newXtReserve);
        // console.log("new lendApr:", newLendApr);
        // console.log("new borrowApr:", newBorrowApr);
    }

    function lendToOrder(uint256 lendAmt) public {
        (uint256 oriFtReserve, uint256 oriXtReserve) = order.tokenReserves();
        (uint256 oriLendApr, uint256 oriBorrowApr) = order.apr();
        uint256 oriFtBalance = ft.balanceOf(userAddr);

        vm.startBroadcast(userPrivateKey);
        lendAmt = lendAmt * 10 ** underlying.decimals();
        uint256 oriUnderlyingBalance = underlying.balanceOf(userAddr);
        underlying.approve(address(order), lendAmt);
        order.swapExactTokenToToken(underlying, ft, userAddr, uint128(lendAmt), 0, uint128(0));
        vm.stopBroadcast();

        (uint256 newFtReserve, uint256 newXtReserve) = order.tokenReserves();
        (uint256 newLendApr, uint256 newBorrowApr) = order.apr();
        uint256 newUnderlyingBalance = underlying.balanceOf(userAddr);
        uint256 newFtBalance = ft.balanceOf(userAddr);

        // console.log("--- Lend to order ---");
        // console.log("ori ftReserve:", oriFtReserve);
        // console.log("ori xtReserve:", oriXtReserve);
        // console.log("ori lendApr:", oriLendApr);
        // console.log("ori borrowApr:", oriBorrowApr);
        // console.log("ori underlyingBalance:", oriUnderlyingBalance);
        // console.log("ori ftBalance:", oriFtBalance);
        // console.log("new ftReserve:", newFtReserve);
        // console.log("new xtReserve:", newXtReserve);
        // console.log("new lendApr:", newLendApr);
        // console.log("new borrowApr:", newBorrowApr);
        // console.log("new underlyingBalance:", newUnderlyingBalance);
        // console.log("new ftBalance:", newFtBalance);
    }

    function borrowFromOrder(uint256 collateralAmt, uint256 borrowAmt, uint256 maxDebtAmt)
        public
        returns (uint256 gtId)
    {
        collateralAmt = collateralAmt * 10 ** collateral.decimals();
        borrowAmt = borrowAmt * 10 ** underlying.decimals();
        maxDebtAmt = maxDebtAmt * 10 ** underlying.decimals();
        (uint256 oriFtReserve, uint256 oriXtReserve) = order.tokenReserves();
        (uint256 oriLendApr, uint256 oriBorrowApr) = order.apr();
        uint256 oriUnderlyingBalance = underlying.balanceOf(userAddr);

        vm.startBroadcast(userPrivateKey);
        uint256 oriCollateralBalance = collateral.balanceOf(userAddr);
        // uint256 fee = (market.issueGtFeeRatio() * maxDebtAmt) / Constants.DECIMAL_BASE;
        // uint256 ftAmt = maxDebtAmt - fee;
        collateral.approve(address(router), collateralAmt);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = order;
        uint128[] memory ftAmtsToSell = new uint128[](1);
        ftAmtsToSell[0] = uint128(borrowAmt);
        SwapUnit[] memory units = new SwapUnit[](0);
        (gtId,) = router.leverageFromToken(
            userAddr,
            market,
            orders,
            ftAmtsToSell,
            uint128(0), // minXtOut
            uint128(borrowAmt), // tokenToSwap
            uint128(maxDebtAmt), // maxLtv
            units,
            block.timestamp
        );
        vm.stopBroadcast();

        (uint256 newFtReserve, uint256 newXtReserve) = order.tokenReserves();
        (uint256 newLendApr, uint256 newBorrowApr) = order.apr();
        uint256 newUnderlyingBalance = underlying.balanceOf(userAddr);
        uint256 newCollateralBalance = collateral.balanceOf(userAddr);

        // console.log("--- Borrow from order ---");
        // console.log("ori ftReserve:", oriFtReserve);
        // console.log("ori xtReserve:", oriXtReserve);
        // console.log("ori lendApr:", oriLendApr);
        // console.log("ori borrowApr:", oriBorrowApr);
        // console.log("ori underlyingBalance:", oriUnderlyingBalance);
        // console.log("ori collateralBalance:", oriCollateralBalance);
        // console.log("new ftReserve:", newFtReserve);
        // console.log("new xtReserve:", newXtReserve);
        // console.log("new lendApr:", newLendApr);
        // console.log("new borrowApr:", newBorrowApr);
        // console.log("new underlyingBalance:", newUnderlyingBalance);
        // console.log("new collateralBalance:", newCollateralBalance);
    }

    function leverageFromOrder(uint128 amtToBuyXt, uint128 minXtOut, uint128 tokenToSwap, uint128 maxLtv) public {
        amtToBuyXt = uint128(amtToBuyXt * 10 ** underlying.decimals());
        tokenToSwap = uint128(tokenToSwap * 10 ** underlying.decimals());
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
        underlying.approve(address(router), amtToBuyXt + tokenToSwap);
        (uint256 gtId,) = router.leverageFromToken(
            userAddr, market, orders, amtsToBuyXt, minXtOut, tokenToSwap, maxLtv, units, block.timestamp + 1 hours
        );
        vm.stopBroadcast();

        (uint256 newFtReserve, uint256 newXtReserve) = order.tokenReserves();
        (uint256 newLendApr, uint256 newBorrowApr) = order.apr();
        uint256 newUnderlyingBalance = underlying.balanceOf(userAddr);
        // uint256 newCollateralBalance = collateral.balanceOf(userAddr);

        // console.log("--- Leverage from order ---");
        // console.log("ori ftReserve:", oriFtReserve);
        // console.log("ori xtReserve:", oriXtReserve);
        // console.log("ori lendApr:", oriLendApr);
        // console.log("ori borrowApr:", oriBorrowApr);
        // console.log("ori underlyingBalance:", oriUnderlyingBalance);
        // console.log("new ftReserve:", newFtReserve);
        // console.log("new xtReserve:", newXtReserve);
        // console.log("new lendApr:", newLendApr);
        // console.log("new borrowApr:", newBorrowApr);
        // console.log("new underlyingBalance:", newUnderlyingBalance);
    }

    function addCollateral(uint256 gtId, uint256 addCollateralAmt) public {
        addCollateralAmt = addCollateralAmt * 10 ** collateral.decimals();
        vm.startBroadcast(userPrivateKey);
        collateral.approve(address(gt), addCollateralAmt);
        gt.addCollateral(gtId, abi.encode(addCollateralAmt));
        vm.stopBroadcast();
    }

    function removeCollateral(uint256 gtId, uint256 removeCollateralAmt) public {
        removeCollateralAmt = removeCollateralAmt * 10 ** collateral.decimals();
        vm.startBroadcast(userPrivateKey);
        gt.removeCollateral(gtId, abi.encode(removeCollateralAmt));
        vm.stopBroadcast();
    }

    function repay(uint256 gtId, uint128 repayAmt, bool byDebtToken) public {
        repayAmt = uint128(repayAmt * 10 ** underlying.decimals());
        vm.startBroadcast(userPrivateKey);
        underlying.approve(address(gt), repayAmt);
        gt.repay(gtId, repayAmt, byDebtToken);
        vm.stopBroadcast();
    }

    function transferGT(uint256 gtId, address toAddr) public {
        vm.startBroadcast(userPrivateKey);
        gt.transferFrom(userAddr, toAddr, gtId);
        vm.stopBroadcast();
        // console.log("Transfer GT No. %d from %s to %s", gtId, userAddr, toAddr);
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
        console.log("mintGtFeeRatio:", config.feeConfig.mintGtFeeRatio);
        console.log("mintGtFeeRef:", config.feeConfig.mintGtFeeRef);
        console.log("");
    }

    function printUserPosition() public view {
        console.log("--- User Position ---");
        console.log("User Addr:", userAddr);
        console.log("Market Addr:", address(market));
        (IERC20[4] memory tokens, uint256[4] memory balances, address gtAddr, uint256[] memory gtIds) =
            router.assetsWithERC20Collateral(market, address(0x2A58A3D405c527491Daae4C62561B949e7F87EFE));
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log(IERC20Metadata(address(tokens[i])).symbol(), ":", balances[i]);
        }
        console.log("gtAddr:", gtAddr);
        console.log("gtIds:");
        for (uint256 i = 0; i < gtIds.length; i++) {
            console.log(gtIds[i]);
        }
    }
}
