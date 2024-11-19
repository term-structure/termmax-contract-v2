// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.27;

// import "forge-std/Test.sol";
// import {console} from "forge-std/console.sol";

// import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import {DeployUtils} from "./utils/DeployUtils.sol";
// import {JSONLoader} from "./utils/JSONLoader.sol";
// import {StateChecker} from "./utils/StateChecker.sol";
// import {SwapUtils} from "./utils/SwapUtils.sol";

// import {ITermMaxMarket, TermMaxMarket, Constants, TermMaxCurve} from "../contracts/core/TermMaxMarket.sol";
// import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
// import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
// import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../contracts/core/factory/TermMaxFactory.sol";
// import "../contracts/core/storage/TermMaxStorage.sol";
// import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";
// import {ITermMaxRouter, SwapInput} from "../contracts/router/ITermMaxRouter.sol";
// import {LoanUtils} from "./utils/LoanUtils.sol";

// struct Res {
//     TermMaxFactory factory;
//     ITermMaxMarket market;
//     IMintableERC20 ft;
//     IMintableERC20 xt;
//     IMintableERC20 lpFt;
//     IMintableERC20 lpXt;
//     IGearingToken gt;
//     MockPriceFeed underlyingOracle;
//     MockPriceFeed collateralOracle;
//     IERC20Metadata collateral;
//     IERC20Metadata underlying;
// }

// contract TermMaxRouterLeverageTest is Test {
//     using SafeERC20 for IERC20Metadata;
//     using SafeERC20 for IERC20;
//     bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

//     uint256 internal mainnetFork;
//     address deployer = vm.envAddress("FORK_DEPLOYER_ADDR");
//     string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

//     Res res;

//     MarketConfig marketConfig;

//     address sender = 0x7B635Ad7dEb5e7449ea3734Ac1543F61334B6b9e; // vm.randomAddress();
//     address receiver = sender;

//     address treasurer = 0x8C7547f4B958B383D872B0886bbBC1aF001c5451; // vm.randomAddress();
//     string testdata;
//     ITermMaxRouter router;

//     address pendleRouterAddress = 0x888888888889758F76e7103c6CbF23ABbF58F946;
//     address curveRouterAddress = 0x16C6521Dff6baB339122a0FE25a9116693265353;

//     function setUp() public {
//         vm.startPrank(deployer);
//         mainnetFork = vm.createFork(MAINNET_RPC_URL);
//         vm.selectFork(mainnetFork);
//         vm.rollFork(21173000); // Nov-12-2024 05:09:23 PM +UTC, 1731388163

//         testdata = vm.readFile(
//             string.concat(vm.projectRoot(), "/test/testdata/testdata-fork.json")
//         );

//         uint32 maxLtv = 0.95e8;
//         uint32 liquidationLtv = 0.96e8;

//         marketConfig = JSONLoader.getMarketConfigFromJson(
//             treasurer,
//             testdata,
//             ".marketConfig"
//         );
//         res = deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);
//         console.log("Market address: ", address(res.market));

//         vm.warp(
//             vm.parseUint(
//                 vm.parseJsonString(testdata, ".marketConfig.currentTime")
//             )
//         );

//         // update oracle
//         res.collateralOracle.updateRoundData(
//             MockPriceFeed.RoundData({
//                 roundId: 2,
//                 answer: int(1e1 ** res.collateralOracle.decimals()),
//                 startedAt: 0,
//                 updatedAt: 0,
//                 answeredInRound: 0
//             })
//         );
//         res.underlyingOracle.updateRoundData(
//             MockPriceFeed.RoundData({
//                 roundId: 2,
//                 answer: int(1e1 ** res.underlyingOracle.decimals()),
//                 startedAt: 0,
//                 updatedAt: 0,
//                 answeredInRound: 0
//             })
//         );

//         uint amount = 1_000_000e6;
//         deal(address(res.underlying), deployer, amount);

//         res.underlying.approve(address(res.market), amount);
//         res.market.provideLiquidity(amount);

//         router = DeployUtils.deployRouter(deployer);
//         router.setMarketWhitelist(address(res.market), true);
//         router.setSwapperWhitelist(pendleRouterAddress, true);
//         router.setSwapperWhitelist(curveRouterAddress, true);
//         router.togglePause(false);

//         console.log("sender", address(sender));
//         console.log("treasurer", address(treasurer));
//         console.log("Market address: ", address(res.market));
//         console.log("Factory address: ", address(res.factory));
//         console.log("FT address: ", address(res.ft));
//         console.log("XT address: ", address(res.xt));
//         console.log("LPFT address: ", address(res.lpFt));
//         console.log("LPXT address: ", address(res.lpXt));
//         console.log("GT address: ", address(res.gt));
//         console.log("Collateral address: ", address(res.collateral));
//         console.log("Underlying address: ", address(res.underlying));
//         console.log(
//             "Underlying Oracle address: ",
//             address(res.underlyingOracle)
//         );
//         console.log(
//             "Collateral Oracle address: ",
//             address(res.collateralOracle)
//         );

//         vm.stopPrank();
//     }

//     function testLeverageFromToken() public {
//         vm.startPrank(sender);

//         uint128 underlyingAmtInForBuyXt = 500e6;
//         uint128 minXTOut = 0e8;
//         uint256 minCollAmt = 0;
//         deal(address(res.underlying), sender, underlyingAmtInForBuyXt);
//         res.underlying.approve(address(router), underlyingAmtInForBuyXt);

//         bytes
//             memory swapData = hex"c81f847a0000000000000000000000006d5d327ab16f175144fce4345434a30e48549301000000000000000000000000cdd26eb5eb2ce0f203a84553853667ae69ca29ce00000000000000000000000000000000000000000000001c7684b7fd4a32df6100000000000000000000000000000000000000000000000e600f4ffea198667900000000000000000000000000000000000000000000001e302027fd202670cb00000000000000000000000000000000000000000000001cc01e9ffd4330ccf3000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000038d7ea4c6800000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000b00000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000001dcd65000000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b30000000000000000000000001e8b6ac39f8a33f46a6eb2d1acd1047b99180ad100000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000006131b5fae19ea4f9d964eac0408e4408b66337b5000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000864e21fd0e90000000000000000000000000000000000000000000000000000000000000020000000000000000000000000f081470f5c6fbccf48cc4e5b82dd926409dcdd67000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003a000000000000000000000000000000000000000000000000000000000000005e000000000000000000000000000000000000000000000000000000000000002e0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b3000000000000000000000000888888888889758f76e7103c6cbf23abbf58f946000000000000000000000000000000000000000000000000000000007fffffff00000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004063407a490000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000f081470f5c6fbccf48cc4e5b82dd926409dcdd67000000000000000000000000e6d7ebb9f1a9519dc06d557e03c522d53520e76a000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b3000000000000000000000000000000000000000000000000000000001dcd650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000001c68fa1a58d49000000000000001b180d24485f23adbb000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b3000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000888888888889758f76e7103c6cbf23abbf58f946000000000000000000000000000000000000000000000000000000001dcd650000000000000000000000000000000000000000000000001ad2b0d9ae0c449a12000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000f081470f5c6fbccf48cc4e5b82dd926409dcdd670000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000001dcd650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002317b22536f75726365223a2250656e646c65222c22416d6f756e74496e555344223a223530302e31363236363438383536353932222c22416d6f756e744f7574555344223a223530332e3235363231303039313535363937222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a22343939373935313731333135303137383231363237222c2254696d657374616d70223a313733313434343539372c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a22484a6c7074593866374c4464776c6d38615857656b354272483066666f502b336f6575695058526f6d55376b32354d4831787130376638614a7152364533454549747643384b334758375579616d795957526e72564648764e745a53366436654853306e793442425a424f703052502f794556543853526e2f4b346d417a586567626552336d786442584f33704f4a343330714a744f636b6678306a654e3978573746716165597a464a766d583367584f414e2f77356d63343157505738577839754e31436e366a5975694c67324a773076732b46575077306b6c6c58543046456c4847694b31344c6965624973704c3446526e4b54585539764e3462524d75497667302b5161386535514865543041585738714870585172344531466f773250703845622f3445745637736d524f662f5476455774386c68464b4c5630612f4c6a314b644e494977314d384c4b546e4464544854673d3d227d7d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

//         SwapInput memory swapInput = SwapInput(
//             pendleRouterAddress, // swapper
//             swapData,
//             res.underlying,
//             res.collateral
//         );

//         //   router.leverageFromToken(receiver, res.market, underlyingAmtInForBuyXt, minCollAmt, minXTOut, swapInput);

//         vm.stopPrank();
//     }

//     // function testLeverageFromXt() public {
//     //     vm.startPrank(sender);

//     //     uint128 underlyingAmtIn = 1_000e6;
//     //     uint128 minTokenOut = 0e8;
//     //     deal(address(res.underlying), sender, underlyingAmtIn);

//     //     res.underlying.approve(address(router), underlyingAmtIn);
//     //     uint256 netXtOut = router.swapExactTokenForXt(receiver, res.market, underlyingAmtIn, minTokenOut);
//     //     uint256 xtInAmt = netXtOut;

//     //     uint256 minCollAmt = 100e18 * 2;
//     //     bytes memory swapData = abi.encodeWithSelector(
//     //         IMintableERC20.mint.selector,
//     //         address(router),
//     //         minCollAmt
//     //     );
//     //     SwapInput memory swapInput = SwapInput(
//     //         address(res.collateral), // swapper
//     //         swapData,
//     //         res.underlying,
//     //         res.collateral
//     //     );
//     //     res.xt.approve(address(router), xtInAmt);
//     //     router.leverageFromXt(receiver, res.market, xtInAmt, minCollAmt, swapInput);

//     //     vm.stopPrank();
//     // }

//     function deployMarket(
//         address deployer,
//         MarketConfig memory marketConfig,
//         uint32 maxLtv,
//         uint32 liquidationLtv
//     ) internal returns (Res memory res) {
//         res.factory = new TermMaxFactory(deployer);

//         TermMaxMarket m = new TermMaxMarket();
//         res.factory.initMarketImplement(address(m));

//         res.collateral = IERC20Metadata(
//             0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81
//         ); // PT Ethena sUSDE 27MAR2025
//         res.underlying = IERC20Metadata(
//             0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
//         ); // USDC

//         res.underlyingOracle = new MockPriceFeed(deployer);
//         res.collateralOracle = new MockPriceFeed(deployer);

//         MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
//             roundId: 1,
//             answer: int(1e1 ** res.collateralOracle.decimals()),
//             startedAt: 0,
//             updatedAt: 0,
//             answeredInRound: 0
//         });
//         MockPriceFeed(address(res.collateralOracle)).updateRoundData(roundData);

//         ITermMaxFactory.DeployParams memory params = ITermMaxFactory
//             .DeployParams({
//                 gtKey: GT_ERC20,
//                 admin: deployer,
//                 collateral: address(res.collateral),
//                 underlying: res.underlying,
//                 underlyingOracle: res.underlyingOracle,
//                 liquidationLtv: liquidationLtv,
//                 maxLtv: maxLtv,
//                 liquidatable: true,
//                 marketConfig: marketConfig,
//                 gtInitalParams: abi.encode(res.collateralOracle)
//             });

//         res.market = ITermMaxMarket(res.factory.createMarket(params));
//         (res.ft, res.xt, res.lpFt, res.lpXt, res.gt, , ) = res.market.tokens();
//     }
// }
