// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {CurveCuts} from "contracts/v1/storage/TermMaxStorage.sol";
import {OrderV2ConfigurationParams} from "contracts/v2/vault/VaultStorageV2.sol";
import {SwapUnit} from "contracts/v1/router/ISwapAdapter.sol";
import {SwapPath} from "contracts/v2/router/ITermMaxRouterV2.sol";
import {TermMaxRouterV2} from "contracts/v2/router/TermMaxRouterV2.sol";
import {RouterErrors} from "contracts/v1/errors/RouterErrors.sol";
import {TermMaxRouterV2_02} from "contracts/v2/router/TermMaxRouterV2_02.sol";
import {FlashLoanProvider} from "contracts/v2/router/ITermMaxRouterV2_02.sol";
import {ITermMaxVaultV2 as IVaultV2} from "contracts/v2/vault/ITermMaxVaultV2.sol";
import {TermMaxSwapAdapter, TermMaxSwapData} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
import {MockWhitelistManager} from "contracts/v2/test/MockWhitelistManager.sol";
import {IWhitelistManager} from "contracts/v2/access/IWhitelistManager.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";

/// @dev Curator-only hook used to lift an order's borrow-side capacity.
interface IVaultCurator {
    function updateOrdersConfiguration(address[] memory orders, OrderV2ConfigurationParams[] memory orderConfigs)
        external;
}

/// @dev The AMM's virtual XT reserve caps how much ft an order can absorb.
interface IOrderV2Ext {
    function virtualXtReserve() external view returns (uint256);
}

/// @notice Rolls EVERY live position of the RLUSD/USPC market maturing 2026-09-15 into the next
///         market (2026-10-25), one flash rollover per position, with Morpho as the flash loan
///         liquidity provider.
///
///         Everything but the routers is mainnet state at the pinned block: both markets, the
///         Coinshift rlUSD vault that makes the market on each of them, the vault's order on the
///         old market that the ft is redeemed out of, and the vault's order on the new market the
///         freshly issued ft is sold into. The routers are deployed on the fork because this
///         exercises the router code under test.
contract ForkRollAllRlusdPositions is Test {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 constant FORK_BLOCK = 25889473;

    IMorphoFlashLender morpho = IMorphoFlashLender(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    // RLUSD / USPC, maturing 2026-09-15 -> 2026-10-25
    ITermMaxMarket oldMarket = ITermMaxMarket(0x4A640c87d048DBcDB1F27e1a5882fb7947446E7d);
    ITermMaxMarket newMarket = ITermMaxMarket(0x163c7607D9838793Af8dB2C6940cf275D503b379);

    /// @dev Coinshift rlUSD vault: the maker of both orders below, and the source of the old ft
    IVaultV2 vault = IVaultV2(0x7A84fCB839BEb377861001c6339a986B9e6d6D68);
    address curator = 0x67460001C991708c6A6BAFc511a60c2E414D7Ecf;
    /// @dev the vault's order on each market, found by walking the market's CREATE nonces
    address oldOrder = 0x4619Cb0446DA38ee381E6FD15ab9161C134b2E18;
    ITermMaxOrder newOrder = ITermMaxOrder(0x7917B6Eff4B4FdFC6C2512D0fE95457a2Fd3d098);

    uint256[] gtIds = [1, 2, 3, 4, 7, 8, 9, 10, 11, 12];

    /// @dev The new market caps a fresh position at 87.5% ltv, and these positions sit at 74.6%
    ///      to 86.8%, so the debt each one may be issued with is bounded by that headroom rather
    ///      than by a flat percentage. A hair is left under the cap for rounding.
    uint256 constant NEW_MARKET_MAX_LTV = 87_500_000;
    uint256 constant LTV_SAFETY = 100_000; // 0.1%

    TermMaxRouterV2 routerV2;
    TermMaxRouterV2_02 router02;
    address tmxAdapter;

    IERC20 rlusd;
    IERC20 uspc;
    IERC20 oldFt;
    IERC20 newFt;
    IGearingToken oldGt;
    IGearingToken newGt;

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, FORK_BLOCK);

        address collateral;
        IERC20 debtToken;
        (oldFt,, oldGt, collateral, debtToken) = oldMarket.tokens();
        (newFt,, newGt,,) = newMarket.tokens();
        rlusd = debtToken;
        uspc = IERC20(collateral);

        // the routers under test, with a permissionless whitelist registering what the flow touches
        MockWhitelistManager wm = new MockWhitelistManager();
        routerV2 = TermMaxRouterV2(
            address(
                new ERC1967Proxy(
                    address(new TermMaxRouterV2(address(wm))),
                    abi.encodeCall(TermMaxRouterV2.initialize, (address(this)))
                )
            )
        );
        router02 = TermMaxRouterV2_02(
            address(
                new ERC1967Proxy(
                    address(new TermMaxRouterV2_02(address(wm))),
                    abi.encodeCall(TermMaxRouterV2_02.initialize, (address(this)))
                )
            )
        );
        tmxAdapter = address(new TermMaxSwapAdapter(address(wm)));

        address[] memory markets = new address[](2);
        markets[0] = address(oldMarket);
        markets[1] = address(newMarket);
        wm.batchSetWhitelist(markets, IWhitelistManager.ContractModule.MARKET, true);
        address[] memory adapters = new address[](1);
        adapters[0] = tmxAdapter;
        wm.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);
        // both orders use the vault itself as their swapTrigger callback
        address[] memory callbacks = new address[](1);
        callbacks[0] = address(vault);
        wm.batchSetWhitelist(callbacks, IWhitelistManager.ContractModule.ORDER_CALLBACK, true);

        vm.label(address(morpho), "morpho");
        vm.label(address(oldMarket), "oldMarket");
        vm.label(address(newMarket), "newMarket");
        vm.label(address(vault), "rlusdVault");
        vm.label(oldOrder, "oldOrder");
        vm.label(address(newOrder), "newOrder");
        vm.label(address(rlusd), "RLUSD");
        vm.label(address(uspc), "USPC");
        vm.label(address(router02), "router02");
        vm.label(address(routerV2), "routerV2");
    }

    /// @dev Zero runs against the order exactly as it stands on chain, which is what this now
    ///      does: the curator lifted virtualXtReserve to 30M at block 25890403. Set CAPACITY_BPS
    ///      (in bps of the rolled size) to simulate a different capacity instead.
    uint256 capacityBps = vm.envOr("CAPACITY_BPS", uint256(0));

    /// @dev The order has to be able to absorb the whole rolled size on its borrow side, and it
    ///      is `virtualXtReserve` that the borrow side spends — not maxXtReserve, and not the
    ///      curve. The curator's first expansion scaled the curve and maxXtReserve from 20M to
    ///      30M but left this reserve at 11.18M, which was 93.8% of the rolled size and died on
    ///      the seventh position with InsufficientLiquidity.
    function testOrderCapacityCoversTheBatch() public view {
        uint256 reserve = IOrderV2Ext(address(newOrder)).virtualXtReserve();
        uint256 totalDebt;
        for (uint256 i = 0; i < gtIds.length; ++i) {
            (, uint128 debt,) = oldGt.loanInfo(gtIds[i]);
            totalDebt += debt;
        }
        console.log("virtualXtReserve  RLUSD ", _rlusd(reserve));
        console.log("rolled size       RLUSD ", _rlusd(totalDebt));
        assertGe(reserve, totalDebt, "the order can absorb the whole batch");
    }

    function testRollAllPositions() public {
        uint256 totalDebt;
        uint256 totalCollateral;
        for (uint256 i = 0; i < gtIds.length; ++i) {
            (, uint128 debt, bytes memory collData) = oldGt.loanInfo(gtIds[i]);
            totalDebt += debt;
            totalCollateral += abi.decode(collData, (uint256));
        }
        console.log("positions:               ", gtIds.length);
        console.log("total debt        RLUSD ", _rlusd(totalDebt));
        console.log("total collateral  USPC  ", _uspc(totalCollateral));
        console.log("old order ft      RLUSD ", _rlusd(oldFt.balanceOf(oldOrder)));
        console.log("morpho liquidity  RLUSD ", _rlusd(rlusd.balanceOf(address(morpho))));

        // the new order has to absorb the whole rolled size on its borrow side
        // the curator's on-chain expansion scaled the curve and maxXtReserve but left
        // virtualXtReserve at 11.18M, which is what the borrow side actually spends
        if (capacityBps != 0) _raiseOrderCapacity(address(newOrder), totalDebt * capacityBps / 10000);
        // the vault funds each ft sale out of its own liquidity, so the biggest position goes
        // first, while that liquidity is untouched
        _sortIdsByDebtDesc();

        /// @dev The ft that repays the old positions is redeemed out of the vault's order on the
        /// old market, and that order holds less ft than the positions owe. One borrower brings
        /// the difference and pays it into their own position, so what is left to roll fits the
        /// ft that is actually there.
        uint256 prepared = _prefundTheGap(totalDebt, oldFt.balanceOf(oldOrder));
        console.log("borrower prepared RLUSD ", _rlusd(prepared));

        uint256 rolledDebt;
        uint256 rolledNewDebt;
        uint256 rolledCollateral;
        uint256 rolled;
        for (uint256 i = 0; i < gtIds.length; ++i) {
            (uint256 newGtId, uint256 debt, uint256 collateralAmt, uint256 newDebt) = _roll(gtIds[i]);
            rolledDebt += debt;
            rolledNewDebt += newDebt;
            rolledCollateral += collateralAmt;
            ++rolled;
            console.log("--- gt", gtIds[i], "-> new gt", newGtId);
            console.log(
                string.concat(
                    "    debt  ", _rlusd(debt), " -> ", _rlusd(newDebt), "   collateral ", _uspc(collateralAmt)
                )
            );
        }
        console.log("positions rolled:", rolled, "of", gtIds.length);
        console.log("rolled debt       RLUSD ", _rlusd(rolledDebt));
        console.log("new debt          RLUSD ", _rlusd(rolledNewDebt));
        assertEq(rolled, gtIds.length, "every position was rolled");
        assertEq(rolledCollateral, totalCollateral, "every wei of collateral moved");
        assertEq(rolledDebt + prepared, totalDebt, "the debt was either rolled or paid off in cash");
        // the vault's order on the old market held less ft than the positions owe, and every wei
        // of it went into the rollovers
        assertLe(oldFt.balanceOf(oldOrder), 1e18, "the old order's ft is spent");
        assertEq(rlusd.balanceOf(address(router02)), 0, "router02 holds no debt token");
        assertEq(uspc.balanceOf(address(router02)), 0, "router02 holds no collateral");
        assertEq(IERC20(address(vault)).balanceOf(address(router02)), 0, "router02 holds no vault shares");
    }

    // ------------------------------------------------------------------
    // Logging helpers: raw wei is unreadable at these sizes
    // ------------------------------------------------------------------

    /// @dev 1311217835726276798002526 RLUSD reads as "1,311,217.835726"
    function _rlusd(uint256 amount) internal pure returns (string memory) {
        return _amount(amount, 18, 6);
    }

    /// @dev 13974312186380 USPC reads as "13,974,312.186380"
    function _uspc(uint256 amount) internal pure returns (string memory) {
        return _amount(amount, 6, 6);
    }

    /// @dev 87500000 ltv reads as "87.50%"
    function _pct(uint256 ltv) internal pure returns (string memory) {
        return string.concat(_amount(ltv, 6, 2), "%");
    }

    function _amount(uint256 amount, uint8 decimals, uint8 shown) internal pure returns (string memory) {
        uint256 unit = 10 ** decimals;
        uint256 frac = (amount % unit) / (10 ** (decimals - shown));
        string memory fracStr = Strings.toString(frac);
        // left pad the fraction so 0.05 does not read as 0.5
        while (bytes(fracStr).length < shown) {
            fracStr = string.concat("0", fracStr);
        }
        return string.concat(_grouped(amount / unit), ".", fracStr);
    }

    /// @dev Thousands separators, so eleven million is countable at a glance
    function _grouped(uint256 value) internal pure returns (string memory) {
        bytes memory digits = bytes(Strings.toString(value));
        if (digits.length < 4) return string(digits);
        bytes memory out = new bytes(digits.length + (digits.length - 1) / 3);
        uint256 w = out.length;
        for (uint256 i = 0; i < digits.length; ++i) {
            if (i != 0 && i % 3 == 0) out[--w] = ",";
            out[--w] = digits[digits.length - 1 - i];
        }
        return string(out);
    }

    /// @dev One borrower fronts the whole shortfall and pays it straight into their own position,
    ///      in a single transaction, before any rolling starts. That lowers their debt (and their
    ///      ltv), and leaves the total owed exactly equal to the ft the order can supply, so every
    ///      other position — down to the smallest — still finds ft when its turn comes.
    function _prefundTheGap(uint256 totalDebt, uint256 availableFt) internal returns (uint256 prepared) {
        if (totalDebt <= availableFt) return 0;
        // a wei of slack so the last pull can not come up short
        uint256 gap = totalDebt - availableFt + 1;
        console.log("old order ft is short by  RLUSD ", _rlusd(gap - 1));
        for (uint256 i = 0; i < gtIds.length; ++i) {
            (address borrower, uint128 debt,) = oldGt.loanInfo(gtIds[i]);
            if (debt < gap) continue;
            console.log(string.concat("gt ", Strings.toString(gtIds[i]), " tops up the gap  RLUSD ", _rlusd(gap)));
            deal(address(rlusd), borrower, rlusd.balanceOf(borrower) + gap);
            vm.startPrank(borrower);
            rlusd.approve(address(oldGt), gap);
            oldGt.repay(gtIds[i], uint128(gap), true);
            vm.stopPrank();
            return gap;
        }
        revert("no single position is big enough to cover the gap");
    }

    /// @dev Largest debt first: every sale is funded by the vault, and the later ones have less
    ///      of its liquidity left to draw on.
    function _sortIdsByDebtDesc() internal {
        for (uint256 i = 0; i < gtIds.length; ++i) {
            for (uint256 j = i + 1; j < gtIds.length; ++j) {
                (, uint128 a,) = oldGt.loanInfo(gtIds[i]);
                (, uint128 b,) = oldGt.loanInfo(gtIds[j]);
                if (b > a) {
                    uint256 tmp = gtIds[i];
                    gtIds[i] = gtIds[j];
                    gtIds[j] = tmp;
                }
            }
        }
    }

    /// @dev Roll one position: the whole debt and the whole collateral, funded by a Morpho flash
    ///      loan of the debt token.
    function _roll(uint256 gtId)
        internal
        returns (uint256 newGtId, uint256 debt, uint256 collateralAmt, uint256 newDebt)
    {
        address borrower;
        uint256 fullDebt;
        uint256 fullCollateral;
        {
            uint128 debt128;
            bytes memory collData;
            (borrower, debt128, collData) = oldGt.loanInfo(gtId);
            fullDebt = debt128;
            fullCollateral = abi.decode(collData, (uint256));
        }
        /// @dev The ft that repays the old position is redeemed out of the vault's order on the
        /// old market, so a position can only be rolled as far as that order's ft stretches. The
        /// last one is rolled partially, taking its collateral out in the same proportion so the
        /// remainder keeps the ltv it had.
        assertLe(fullDebt, oldFt.balanceOf(oldOrder), "the order has the ft this position needs");
        debt = fullDebt;
        collateralAmt = fullCollateral;

        // the most debt this collateral may carry in the new market
        uint128 maxDebtAmt;
        {
            (, uint128 ltv,) = oldGt.getLiquidationInfo(gtId);
            maxDebtAmt = uint128(debt * (NEW_MARKET_MAX_LTV - LTV_SAFETY) / ltv);
            console.log(
                string.concat(
                    "    ltv ", _pct(ltv), " -> issuable ", _rlusd(maxDebtAmt), " against debt ", _rlusd(debt)
                )
            );
        }
        bytes memory rolloverData;
        {
            uint128 expectedFtOut = maxDebtAmt - uint128(uint256(maxDebtAmt) * newMarket.mintGtFeeRatio() / 1e8);
            address[] memory orders = new address[](1);
            orders[0] = address(newOrder);
            uint128[] memory tradingAmts = new uint128[](1);
            /// @dev The sale is quoted at exactly what the flash loan has to give back, the same
            /// `previewMint(previewWithdraw(debt))` the router computes. That is not a nicety: the
            /// vault has no idle liquidity here, the liquidity that buys this ft is the flash loan
            /// the router just minted into it, so a sale quoted above it asks the vault for money
            /// it does not have and reverts with ERC4626ExceededMaxWithdraw.
            tradingAmts[0] =
                uint128(IERC4626(address(vault)).previewMint(IERC4626(address(vault)).previewWithdraw(debt)));
            TermMaxSwapData memory swapData = TermMaxSwapData({
                swapExactTokenForToken: false,
                scalingFactor: 0,
                orders: orders,
                tradingAmts: tradingAmts,
                netTokenAmt: expectedFtOut,
                deadline: block.timestamp,
                refundAddress: address(routerV2)
            });
            SwapUnit[] memory units = new SwapUnit[](1);
            units[0] = SwapUnit({
                adapter: tmxAdapter, tokenIn: address(newFt), tokenOut: address(rlusd), swapData: abi.encode(swapData)
            });
            SwapPath memory sellFtPath = SwapPath({
                inputAmount: expectedFtOut, recipient: address(router02), useBalanceOnchain: true, units: units
            });
            rolloverData = abi.encode(address(routerV2), collateralAmt, newMarket, maxDebtAmt, sellFtPath);
        }

        address[] memory ftOrders = new address[](1);
        ftOrders[0] = oldOrder;
        uint256[] memory ftAmounts = new uint256[](1);
        ftAmounts[0] = debt;

        vm.startPrank(borrower);
        IERC721(address(oldGt)).approve(address(router02), gtId);
        newGtId = router02.flashRolloverGt(
            oldMarket,
            gtId,
            uint128(debt),
            IERC20(address(0)),
            0,
            FlashLoanProvider.MORPHO,
            address(morpho),
            vault,
            ftOrders,
            ftAmounts,
            rolloverData
        );
        vm.stopPrank();

        // the rolled part of the old position is gone, the rest (if any) stays put
        (, uint128 debtAfter, bytes memory collAfter) = oldGt.loanInfo(gtId);
        assertEq(debtAfter, fullDebt - debt, "old debt reduced by what was rolled");
        assertEq(abi.decode(collAfter, (uint256)), fullCollateral - collateralAmt, "old collateral reduced");
        address newOwner;
        {
            uint128 newDebt128;
            bytes memory newCollData;
            (newOwner, newDebt128, newCollData) = newGt.loanInfo(newGtId);
            newDebt = newDebt128;
            assertEq(abi.decode(newCollData, (uint256)), collateralAmt, "collateral carried over");
        }
        assertEq(newOwner, borrower, "the borrower owns the new position");
        assertGe(newDebt, debt, "the new debt covers the rolled debt");
        assertLe(newDebt, maxDebtAmt, "the new debt stays within the issued debt");
    }

    /// @dev Prank the vault curator to lift the order's virtual/max XT reserve so its curve can
    ///      price the ft the rollovers sell into it. The existing curve cuts are reused.
    function _raiseOrderCapacity(address order, uint256 targetCapacity) internal {
        CurveCuts memory curveCuts = ITermMaxOrder(order).orderConfig().curveCuts;
        uint256 current = IOrderV2Ext(order).virtualXtReserve();
        console.log(string.concat("lifting order capacity  RLUSD ", _rlusd(current), " -> ", _rlusd(targetCapacity)));

        OrderV2ConfigurationParams[] memory params = new OrderV2ConfigurationParams[](1);
        params[0] = OrderV2ConfigurationParams({
            originalVirtualXtReserve: current,
            virtualXtReserve: targetCapacity,
            maxXtReserve: targetCapacity,
            curveCuts: curveCuts
        });
        address[] memory orders = new address[](1);
        orders[0] = order;

        vm.prank(curator);
        IVaultCurator(address(vault)).updateOrdersConfiguration(orders, params);
    }
}

/// @dev Morpho Blue's flash loan entrypoint (0 fee).
interface IMorphoFlashLender {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}
