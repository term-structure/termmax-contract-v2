// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.27;

// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
// import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
// import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
// import {SwapPath, SwapUnit, ITermMaxRouterV2, TermMaxRouterV2} from "contracts/v2/router/TermMaxRouterV2.sol";
// import {
//     IGearingToken,
//     GearingTokenEvents,
//     AbstractGearingToken,
//     GtConfig
// } from "contracts/v1/tokens/AbstractGearingToken.sol";
// import {PendleSwapV3AdapterV2} from "contracts/v2/router/swapAdapters/PendleSwapV3AdapterV2.sol";
// import {OdosV2AdapterV2} from "contracts/v2/router/swapAdapters/OdosV2AdapterV2.sol";
// import {IOracle} from "contracts/v1/oracle/IOracle.sol";
// import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
// import {
//     ForkBaseTestV2,
//     TermMaxFactoryV2,
//     MarketConfig,
//     IERC20,
//     MarketInitialParams,
//     IERC20Metadata
// } from "test/v2/mainnet-fork/ForkBaseTestV2.sol";
// import {TermMaxSwapData, TermMaxSwapAdapter} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
// import {console} from "forge-std/console.sol";
// import {IAaveV3PoolMinimal} from "contracts/v2/extensions/aave/IAaveV3PoolMinimal.sol";
// import {IAaveV3Minimal} from "contracts/v2/extensions/aave/IAaveV3Minimal.sol";
// import {ICreditDelegationToken} from "contracts/v2/extensions/aave/ICreditDelegationToken.sol";
// import {IMorpho, Id, MarketParams, Authorization, Signature} from "contracts/v2/extensions/morpho/IMorpho.sol";

// interface TestOracle is IOracle {
//     function acceptPendingOracle(address asset) external;
//     function oracles(address asset) external returns (address aggregator, address backupAggregator, uint32 heartbeat);
// }

// contract ForkPrdRollOverToThird is ForkBaseTestV2 {
//     string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
//     string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

//     uint64 may_30 = 1748534400; // 2025-05-30 00:00:00
//     address pt_susde_may_29 = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
//     address pt_susde_jul_31 = 0x3b3fB9C57858EF816833dC91565EFcd85D96f634;
//     address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
//     address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
//     address susde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
//     address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
//     TestOracle oracle = TestOracle(0xE3a31690392E8E18DC3d862651C079339E2c1ADE);

//     ITermMaxMarket mmay_30 = ITermMaxMarket(0xe867255dC0c3a27c90f756ECC566a5292ce19492);

//     ITermMaxMarket mjul_31 = ITermMaxMarket(0xdBB2D44c238c459cCB820De886ABF721EF6E6941);

//     address pendleAdapter;
//     address odosAdapter;
//     address tmxAdapter;
//     address vaultAdapter;
//     TermMaxRouterV2 router;
//     IAaveV3PoolMinimal aave = IAaveV3PoolMinimal(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
//     ICreditDelegationToken aaveDebtToken;

//     IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
//     Id morpho_market_id = Id.wrap(0xbc552f0b14dd6f8e60b760a534ac1d8613d3539153b4d9675d697e048f2edc7e);

//     function _getForkRpcUrl() internal view override returns (string memory) {
//         return MAINNET_RPC_URL;
//     }

//     function _getDataPath() internal view override returns (string memory) {
//         return DATA_PATH;
//     }

//     function _finishSetup() internal override {
//         // vm.rollFork(22486319); // 2025-05-15
//         vm.rollFork(22985670); // 2025-07-24
//         // vm.warp(1747256663);

//         // address accessManager = Ownable(address(oracle)).owner();
//         // vm.startPrank(accessManager);
//         // address[] memory tokens = new address[](4);
//         // tokens[0] = usdc;
//         // tokens[1] = susde;
//         // tokens[2] = pt_susde_may_29;

//         // for (uint256 i = 0; i < tokens.length; i++) {
//         //     address token = tokens[i];
//         //     (address aggregator, address backupAggregator,) = oracle.oracles(token);
//         //     IOracle.Oracle memory oracleData = IOracle.Oracle({
//         //         aggregator: AggregatorV3Interface(aggregator),
//         //         backupAggregator: AggregatorV3Interface(backupAggregator),
//         //         heartbeat: 365 days
//         //     });
//         //     oracle.submitPendingOracle(token, oracleData);
//         // }
//         // vm.warp(block.timestamp + 1 days);
//         // for (uint256 i = 0; i < tokens.length; i++) {
//         //     address token = tokens[i];
//         //     oracle.acceptPendingOracle(token);
//         // }

//         // vm.stopPrank();

//         PendleSwapV3AdapterV2 adapter = new PendleSwapV3AdapterV2(0x888888888889758F76e7103c6CbF23ABbF58F946);
//         pendleAdapter = address(adapter);

//         OdosV2AdapterV2 od = new OdosV2AdapterV2(0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559);
//         odosAdapter = address(od);

//         TermMaxSwapAdapter tmx = new TermMaxSwapAdapter();
//         tmxAdapter = address(tmx);
//         vm.label(tmxAdapter, "TermMaxAdapter");

//         vaultAdapter = address(new ERC4626VaultAdapterV2());
//         vm.label(vaultAdapter, "ERC4626VaultAdapterV2");

//         vm.label(pt_susde_may_29, "pt_susde_may_29");
//         vm.label(susde, "susde");
//         vm.label(address(oracle), "oracle");
//         vm.label(address(mmay_30), "mmay_30");
//         vm.label(address(pendleAdapter), "pendleAdapter");

//         address admin = vm.randomAddress();

//         vm.startPrank(admin);
//         router = deployRouter(admin);
//         router.setAdapterWhitelist(pendleAdapter, true);
//         router.setAdapterWhitelist(odosAdapter, true);
//         router.setAdapterWhitelist(tmxAdapter, true);
//         router.setAdapterWhitelist(vaultAdapter, true);
//         vm.stopPrank();

//         IAaveV3Minimal.ReserveData memory rd = IAaveV3Minimal(address(aave)).getReserveData(usdc);
//         aaveDebtToken = ICreditDelegationToken(rd.variableDebtTokenAddress);
//     }

//     function testDelegateBorrow() public {
//         address user1 = vm.randomAddress();
//         address user2 = vm.randomAddress();
//         vm.label(user1, "user1");
//         vm.label(user2, "user2");

//         // Give user1 some WETH
//         deal(weth, user1, 1 ether);

//         vm.startPrank(user1);

//         deal(weth, user1, 1 ether);
//         IERC20(weth).approve(address(aave), 1 ether);
//         aave.supply(weth, 1 ether, user1, 0);

//         // Get USDC debt token for delegation
//         IAaveV3Minimal.ReserveData memory rd = IAaveV3Minimal(address(aave)).getReserveData(usdc);
//         ICreditDelegationToken usdcDebtToken = ICreditDelegationToken(rd.variableDebtTokenAddress);

//         // Approve delegation to user2
//         usdcDebtToken.approveDelegation(user2, 1000e6); // 1000 USDC delegation limit
//         vm.stopPrank();

//         // Check delegation was successful
//         uint256 allowance = usdcDebtToken.borrowAllowance(user1, user2);
//         require(allowance >= 10e6, "Delegation failed: insufficient allowance");

//         // user2 borrows USDC
//         uint256 borrowAmt = 10e6; // 10 USDC
//         vm.startPrank(user2);
//         uint256 interestRateMode = 2; // Variable rate
//         uint16 referralCode = 0; // No referral code
//         aave.borrow(usdc, borrowAmt, interestRateMode, referralCode, user1);

//         uint256 user2Balance = IERC20(usdc).balanceOf(user2);
//         require(user2Balance == borrowAmt, "Borrow failed: balance mismatch");
//         vm.stopPrank();
//     }

//     function testRolloverPtToAave() public {
//         uint128 debt;
//         uint256 collateralAmount;
//         // deal(pt_susde_may_29, borrower, collateralAmount);
//         uint256 gt1 = 5;
//         address borrower;
//         {
//             (,, IGearingToken gt,,) = mmay_30.tokens();
//             (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(gt1);
//             borrower = owner;
//             debt = debtAmt;
//             collateralAmount = abi.decode(collateralData, (uint256));
//             console.log("collateralAmount:", collateralAmount);
//             console.log("debt:", debt);
//         }
//         {
//             (,, IGearingToken gt,,) = mmay_30.tokens();
//             (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(gt1);
//             borrower = owner;
//             debt = debtAmt;
//             collateralAmount = abi.decode(collateralData, (uint256));
//             console.log("collateralAmount:", collateralAmount);
//             console.log("debt:", debt);
//         }
//         vm.startPrank(borrower);
//         vm.warp(may_30 - 0.5 days);
//         // roll gt
//         {
//             address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;

//             SwapUnit[] memory swapUnits = new SwapUnit[](1);
//             swapUnits[0] = SwapUnit({
//                 adapter: pendleAdapter,
//                 tokenIn: pt_susde_may_29,
//                 tokenOut: susde,
//                 swapData: abi.encode(pm1, collateralAmount, 0)
//             });
//             // swapUnits[1] = SwapUnit({
//             //     adapter: vaultAdapter,
//             //     tokenIn: susde,
//             //     tokenOut: usde,
//             //     swapData: abi.encode(ERC4626VaultAdapterV2.Action.Redeem, 1, 0)
//             // });
//             SwapPath memory collateralPath =
//                 SwapPath({units: swapUnits, recipient: address(router), inputAmount: 0, useBalanceOnchain: true});

//             uint256 additionalAssets = debt / 3;
//             uint256 additionalCollateral = 0;

//             (IERC20 ft,, IGearingToken gt, address collateral,) = mmay_30.tokens();

//             deal(usdc, borrower, additionalAssets);
//             IERC20(usdc).approve(address(router), additionalAssets);
//             aaveDebtToken.approveDelegation(address(router), debt - additionalAssets);
//             gt.approve(address(router), gt1);
//             // 1-stable 2-variable
//             uint256 interestRateMode = 2;
//             uint16 referralCode = 0;
//             router.rollToAaveForV1(
//                 borrower,
//                 mmay_30,
//                 gt1,
//                 additionalCollateral,
//                 additionalAssets,
//                 aave,
//                 interestRateMode,
//                 referralCode,
//                 collateralPath
//             );
//         }

//         vm.stopPrank();
//     }

//     function testRolloverPtToAaveForV2() public {
//         uint128 debt;
//         uint256 collateralAmount;
//         // deal(pt_susde_may_29, borrower, collateralAmount);
//         uint256 gt1 = 5;
//         address borrower;
//         {
//             (,, IGearingToken gt,,) = mmay_30.tokens();
//             (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(gt1);
//             borrower = owner;
//             debt = debtAmt;
//             collateralAmount = abi.decode(collateralData, (uint256));
//             console.log("collateralAmount:", collateralAmount);
//             console.log("debt:", debt);
//         }
//         {
//             (,, IGearingToken gt,,) = mmay_30.tokens();
//             (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(gt1);
//             borrower = owner;
//             debt = debtAmt;
//             collateralAmount = abi.decode(collateralData, (uint256));
//             console.log("collateralAmount:", collateralAmount);
//             console.log("debt:", debt);
//         }
//         vm.startPrank(borrower);
//         vm.warp(may_30 - 0.5 days);
//         // roll gt
//         {
//             address pm1 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;

//             SwapUnit[] memory swapUnits = new SwapUnit[](1);
//             swapUnits[0] = SwapUnit({
//                 adapter: pendleAdapter,
//                 tokenIn: pt_susde_may_29,
//                 tokenOut: susde,
//                 swapData: abi.encode(pm1, collateralAmount, 0)
//             });
//             SwapPath memory collateralPath =
//                 SwapPath({units: swapUnits, recipient: address(router), inputAmount: 0, useBalanceOnchain: true});

//             uint256 additionalAssets = debt / 3;
//             uint256 additionalCollateral = 0;

//             (IERC20 ft,, IGearingToken gt, address collateral,) = mmay_30.tokens();

//             deal(usdc, borrower, additionalAssets);
//             IERC20(usdc).approve(address(router), additionalAssets);
//             aaveDebtToken.approveDelegation(address(router), debt - additionalAssets);
//             gt.approve(address(router), gt1);
//             // 1-stable 2-variable
//             uint256 interestRateMode = 2;
//             uint16 referralCode = 0;
//             router.rollToAaveForV2(
//                 borrower,
//                 mmay_30,
//                 gt1,
//                 debt,
//                 collateralAmount,
//                 additionalCollateral,
//                 additionalAssets,
//                 aave,
//                 interestRateMode,
//                 referralCode,
//                 collateralPath
//             );
//         }

//         vm.stopPrank();
//     }

//     function testRolloverPtToMorphoForV1() public {
//         uint128 debt;
//         uint256 collateralAmount;
//         uint256 gt1 = 1;
//         address borrower;
//         {
//             (,, IGearingToken gt,,) = mjul_31.tokens();
//             (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(gt1);
//             borrower = owner;
//             debt = debtAmt;
//             collateralAmount = abi.decode(collateralData, (uint256));
//             console.log("collateralAmount:", collateralAmount);
//             console.log("debt:", debt);
//         }
//         vm.startPrank(borrower);
//         // roll gt
//         {
//             Id marketId = morpho_market_id;

//             SwapPath memory collateralPath;

//             uint256 additionalAssets = debt / 3;
//             uint256 additionalCollateral = 0;

//             (IERC20 ft,, IGearingToken gt, address collateral,) = mjul_31.tokens();

//             deal(usdc, borrower, additionalAssets);
//             IERC20(usdc).approve(address(router), additionalAssets);
//             // Approve delegation for Morphos
//             morpho.setAuthorization(address(router), true);

//             gt.approve(address(router), gt1);
//             router.rollToMorphoForV1(
//                 borrower, mjul_31, gt1, additionalCollateral, additionalAssets, morpho, morpho_market_id, collateralPath
//             );
//         }

//         vm.stopPrank();
//     }
// }
