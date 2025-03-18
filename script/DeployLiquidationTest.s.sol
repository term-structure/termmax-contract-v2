// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.27;

// import {Script} from "forge-std/Script.sol";
// import {console} from "forge-std/console.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
// import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
// import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
// import {MarketViewer} from "contracts/router/MarketViewer.sol";
// import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
// import {TermMaxMarket, IGearingToken} from "contracts/TermMaxMarket.sol";
// import {TermMaxOrder} from "contracts/TermMaxOrder.sol";
// import {MockERC20} from "contracts/test/MockERC20.sol";
// import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
// import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
// import {IMintableERC20, MintableERC20} from "contracts/tokens/MintableERC20.sol";
// import {SwapAdapter} from "contracts/test/testnet/SwapAdapter.sol";
// import {Faucet} from "contracts/test/testnet/Faucet.sol";
// import {JSONLoader} from "test/utils/JSONLoader.sol";
// import {FaucetERC20} from "contracts/test/testnet/FaucetERC20.sol";
// import {IOracle, OracleAggregator} from "contracts/oracle/OracleAggregator.sol";
// import {IOrderManager, OrderManager} from "contracts/vault/OrderManager.sol";
// import {ITermMaxVault, TermMaxVault} from "contracts/vault/TermMaxVault.sol";
// import {VaultFactory, IVaultFactory} from "contracts/factory/VaultFactory.sol";
// import {
//     MarketConfig,
//     FeeConfig,
//     MarketInitialParams,
//     LoanConfig,
//     VaultInitialParams
// } from "contracts/storage/TermMaxStorage.sol";
// import {KyberswapV2Adapter} from "contracts/router/swapAdapters/KyberswapV2Adapter.sol";
// import {OdosV2Adapter} from "contracts/router/swapAdapters/OdosV2Adapter.sol";
// import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
// import {UniswapV3Adapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";

// contract DeployLiquidationTest is Script {
//     // deployer config
//     uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
//     address deployerAddr = vm.addr(deployerPrivateKey);
//     address treasurer = deployerAddr;

//     bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

//     function run() public {
//         // deploy contracts
//         vm.startBroadcast(deployerPrivateKey);

//         string memory path = string.concat(vm.projectRoot(), "/test/testdata/testdata.json");
//         string memory testdataJSON = vm.readFile(path);
//         MarketConfig memory marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdataJSON, ".marketConfig");
//         marketConfig.maturity = uint64(block.timestamp + 30 days);

//         // deploy tokens
//         MockERC20 collateralToken = new MockERC20("ETH", "ETH", 18);
//         console.log("collateralToken deployed", address(collateralToken));
//         MockERC20 debtToken = new MockERC20("USD", "USD", 8);
//         console.log("debtToken deployed", address(debtToken));

//         // deploy oracle
//         OracleAggregator oracle = new OracleAggregator(deployerAddr, 0);
//         console.log("oracle deployed", address(oracle));
//         MockPriceFeed collateralPriceFeed = new MockPriceFeed(deployerAddr);
//         console.log("collateralPriceFeed deployed", address(collateralPriceFeed));
//         MockPriceFeed debtPriceFeed = new MockPriceFeed(deployerAddr);
//         console.log("debtPriceFeed deployed", address(debtPriceFeed));

//         console.log("oracle submitted oracles");
//         oracle.submitPendingOracle(address(debtToken), IOracle.Oracle(debtPriceFeed, debtPriceFeed, 365 days));
//         oracle.submitPendingOracle(
//             address(collateralToken), IOracle.Oracle(collateralPriceFeed, collateralPriceFeed, 365 days)
//         );
//         console.log("oracle accepted oracles");
//         oracle.acceptPendingOracle(address(debtToken));
//         oracle.acceptPendingOracle(address(collateralToken));

//         MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
//             roundId: 1,
//             answer: int256(2000e8),
//             startedAt: block.timestamp,
//             updatedAt: block.timestamp,
//             answeredInRound: 0
//         });
//         collateralPriceFeed.updateRoundData(roundData);

//         roundData.answer = int256(1e8);
//         debtPriceFeed.updateRoundData(roundData);
//         console.log("price feeds updated");

//         // deploy market
//         address tokenImplementation = address(new MintableERC20());
//         console.log("tokenImplementation deployed", address(tokenImplementation));
//         address orderImplementation = address(new TermMaxOrder());
//         console.log("orderImplementation deployed", address(orderImplementation));
//         TermMaxMarket m = new TermMaxMarket(tokenImplementation, orderImplementation);
//         console.log("market orderImplementation deployed", address(m));
//         TermMaxFactory factory = new TermMaxFactory(deployerAddr, address(m));
//         console.log("factory deployed", address(factory));

//         MarketInitialParams memory initialParams = MarketInitialParams({
//             collateral: address(collateralToken),
//             debtToken: debtToken,
//             admin: deployerAddr,
//             gtImplementation: address(0),
//             marketConfig: marketConfig,
//             loanConfig: LoanConfig({oracle: oracle, liquidationLtv: 0.9e8, maxLtv: 0.88e8, liquidatable: true}),
//             gtInitalParams: abi.encode(type(uint256).max),
//             tokenName: "USD-ETH",
//             tokenSymbol: "USD-ETH"
//         });
//         address market = factory.createMarket(GT_ERC20, initialParams, 0);
//         console.log("market deployed", market);
//         (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt,,) = TermMaxMarket(market).tokens();
//         console.log("ft", address(ft));
//         console.log("xt", address(xt));
//         console.log("gt", address(gt));
//         console.log("minting tokens");
//         collateralToken.mint(deployerAddr, 1000e18);
//         debtToken.mint(deployerAddr, 100000e8);

//         console.log("approving tokens");
//         collateralToken.approve(address(gt), type(uint128).max);
//         debtToken.approve(market, type(uint128).max);

//         console.log("issue Ft");
//         TermMaxMarket(market).issueFt(deployerAddr, 100e8, abi.encode(0.1e18));

//         console.log("price feeds updated");
//         roundData.answer = int256(1000e8);
//         debtPriceFeed.updateRoundData(roundData);

//         vm.stopBroadcast();
//     }
// }
