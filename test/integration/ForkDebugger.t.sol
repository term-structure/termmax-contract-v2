// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../../contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../../contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "../../contracts/router/ITermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../../contracts/TermMaxMarket.sol";
import {ITermMaxMarket} from "../../contracts/TermMaxMarket.sol";
import {MockERC20} from "../../contracts/test/MockERC20.sol";
import {MarketConfig} from "../../contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../../contracts/tokens/IMintableERC20.sol";
import {IGearingToken} from "../../contracts/tokens/IGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../../contracts/test/MockSwapAdapter.sol";
import {Faucet} from "../../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../../contracts/test/testnet/FaucetERC20.sol";
import {SwapUnit} from "../../contracts/router/ISwapAdapter.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";
import {TermMaxOrder, ISwapCallback} from "../../contracts/TermMaxOrder.sol";
import {ITermMaxOrder} from "../../contracts/ITermMaxOrder.sol";
import {OrderConfig} from "../../contracts/storage/TermMaxStorage.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import "contracts/storage/TermMaxStorage.sol";

contract ForkDebugger is Test {
    // EOA config
    uint256 deployerPrivateKey = vm.envUint("HOLESKY_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    uint256 userPrivateKey = vm.envUint("HOLESKY_DEPLOYER_PRIVATE_KEY");
    address userAddr = vm.addr(userPrivateKey);

    // address config
    address faucetAddr = address(0x979963a328dd54b684A522cccb0bA49458dD74ba);
    address routerAddr = address(0x2fA0C6B02F329bc400eB638a764f6CAEa1C11047);
    address swapAdapter = address(0x8be4b9f85C9534C2Fb445E7426858A8AAB1D210a);
    address marketAddr = address(0xAACB14efD381c1659F0bD28c3Ac7cFe8Ad0F342f);
    address orderAddr = address(0x3Cf9Ba89761DFb1C5c370A5f64b692Cd05abcDf6);
    address oracleAggregatorAddr = address(0xd3623A77E2C38E1D528E0a4b1Cd7E5267323a5EC);

    TermMaxRouter router = TermMaxRouter(routerAddr);
    OracleAggregator oracleAggregator = OracleAggregator(oracleAggregator);
    ITermMaxMarket market = ITermMaxMarket(marketAddr);
    TermMaxOrder order = TermMaxOrder(orderAddr);
    IMintableERC20 ft;
    IMintableERC20 xt;
    IGearingToken gt;
    address collateralAddr;
    FaucetERC20 collateral;
    FaucetERC20 underlying;
    IERC20 underlyingERC20;

    ITermMaxMarket testMarket;
    ITermMaxOrder testOrder;
    IMintableERC20 testFt;
    IMintableERC20 testXt;
    IGearingToken testGt;
    address testCollateralAddr;
    FaucetERC20 testCollateral;
    FaucetERC20 testUnderlying;
    IERC20 testUnderlyingERC20;
    OrderConfig orderConfig;
    MarketConfig marketConfig;
    DeployUtils.Res res;
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

    // function setUp() public {
    //     string memory FORK_RPC_URL = vm.envString("HOLESKY_RPC_URL");

    //     uint256 fork = vm.createFork(FORK_RPC_URL);
    //     vm.selectFork(fork);

    //     deployTestContracts();
    // }

    // function deployTestContracts() public {
    //     (ft, xt, gt, collateralAddr, underlyingERC20) = market.tokens();
    //     collateral = FaucetERC20(collateralAddr);
    //     underlying = FaucetERC20(address(underlyingERC20));
    //     marketConfig = market.config();
    //     GtConfig memory gtConfig = gt.getGtConfig();

    //     MarketInitialParams memory initialParams = MarketInitialParams({
    //         collateral: address(collateral),
    //         debtToken: underlying,
    //         admin: deployerAddr,
    //         gtImplementation: address(0),
    //         marketConfig: marketConfig,
    //         loanConfig: LoanConfig({
    //             oracle: oracleAggregator,
    //             liquidationLtv: gtConfig.loanConfig.liquidationLtv,
    //             maxLtv: gtConfig.loanConfig.maxLtv,
    //             liquidatable: true
    //         }),
    //         gtInitalParams: abi.encode(type(uint256).max),
    //         tokenName: "Test Market",
    //         tokenSymbol: "Test Market"
    //     });

    //     vm.startPrank(deployerAddr);
    //     TermMaxFactory testFactory = DeployUtils.deployFactory(deployerAddr);
    //     testMarket = ITermMaxMarket(testFactory.createMarket(GT_ERC20, initialParams, 0));
    //     vm.stopPrank();

    //     vm.startPrank(router.owner());
    //     router.setMarketWhitelist(address(testMarket), true);
    //     vm.stopPrank();

    //     (testFt, testXt, testGt, testCollateralAddr, testUnderlyingERC20) = testMarket.tokens();
    // }

    // function testIntegration() public {
    //     (uint256 oriFtReserve, uint256 oriXtReserve) = order.tokenReserves();
    //     OrderConfig memory testOrderConfig = order.orderConfig();
    //     console.log("ft reserve: %d", oriFtReserve);
    //     console.log("xt reserve: %d", oriXtReserve);
    //     for (uint256 i = 0; i < testOrderConfig.curveCuts.lendCurveCuts.length; i++) {
    //         console.log("lend curve cut - %d", i);
    //         console.log("  - xt reserve: %d", testOrderConfig.curveCuts.lendCurveCuts[i].xtReserve);
    //         console.log("  - liqSquare: %d", testOrderConfig.curveCuts.lendCurveCuts[i].liqSquare);
    //         console.log("  - offset: %d", testOrderConfig.curveCuts.lendCurveCuts[i].offset);
    //     }
    //     for (uint256 i = 0; i < testOrderConfig.curveCuts.borrowCurveCuts.length; i++) {
    //         console.log("borrow curve cut - %d", i);
    //         console.log("  - xt reserve: %d", testOrderConfig.curveCuts.borrowCurveCuts[i].xtReserve);
    //         console.log("  - liqSquare: %d", testOrderConfig.curveCuts.borrowCurveCuts[i].liqSquare);
    //         console.log("  - offset: %d", testOrderConfig.curveCuts.borrowCurveCuts[i].offset);
    //     }
    //     vm.startPrank(userAddr);
    //     testOrder = testMarket.createOrder(
    //         userAddr, testOrderConfig.maxXtReserve, ISwapCallback(address(0)), testOrderConfig.curveCuts
    //     );
    //     uint256 mintAmt = oriFtReserve + oriXtReserve;
    //     underlying.mint(userAddr, mintAmt);
    //     underlying.approve(address(testMarket), mintAmt);
    //     testMarket.mint(userAddr, mintAmt);
    //     testFt.transfer(address(testOrder), oriFtReserve);
    //     testXt.transfer(address(testOrder), oriXtReserve);
    //     vm.stopPrank();
    //     (uint256 oriLendApr, uint256 oriBorrowApr) = testOrder.apr();
    // }
}
