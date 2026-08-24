// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {ITermMaxVaultV2} from "../vault/ITermMaxVaultV2.sol";

/// @notice A third party money market: the external flash loan liquidity source of
///         `flashRolloverGt`, and both the source and the rolled protocol of
///         `rolloverFromLendingProtocol`
enum FlashLoanProvider {
    MORPHO,
    AAVE
}

/**
 * @title TermMax Router V2_02 interface
 * @author Term Structure Labs
 * @notice Extension of TermMaxRouterV2, deployed as a standalone contract because the
 *         main router is close to the EIP-170 bytecode limit. New router features land
 *         here, composing the existing TermMaxRouterV2 functions where possible.
 *         Current features:
 *         - flashRolloverGt: roll a GT position (fully or partially) into a new market,
 *           using an external flash loan (Morpho / Aave) as temporary vault liquidity
 *         - rolloverFromLendingProtocol: roll an Aave / Morpho borrow position (fully or
 *           partially) into a TermMax fixed rate position, using a flash loan from that same
 *           protocol
 */
interface ITermMaxRouterV2_02 {
    /**
     * @notice Rollover a GT position to a new market using an external flash loan as bridging liquidity
     * @notice Applicable scenario: rolling between two markets of the SAME token pair (same
     *         collateral and debt token, differing only in maturity), where both markets are
     *         quoted by the SAME TermMax vault. Designed for the LOW-LIQUIDITY case: the vault
     *         has no idle liquidity to fund a regular rollover, so the flash loan is deposited
     *         as temporary vault liquidity and recycled back within one transaction.
     * @dev The whole flow runs inside a Morpho/Aave flash loan of the debt token. The flash loan
     *      amount is computed on-chain as `vault.previewMint(sum(vault.previewWithdraw(ftAmounts[i])))`
     *      — the exact assets required to mint enough shares for every FT withdrawal:
     *      1. pull the GT from the caller (returned at the end)
     *      2. mint the exact vault shares with the flash-borrowed debt token
     *      3. burn the shares to redeem the old market's FT from a vault order (withdrawFts)
     *      4. `repayAndRemoveCollateral(repayAmt, removedCollateral)` on the old GT in FT —
     *         supports PARTIAL rollover; the GT is never burned and the leftover position
     *         stays intact
     *      5. call `routerV2.borrowTokenFromCollateral` — issues the new FT against exactly
     *         `removedCollateral` and sells it via `swapFtPath`; RouterV2 enforces its own
     *         market and adapter whitelists. The new GT recipient is enforced to this contract
     *         and forwarded to the caller, so it can not be hijacked by malicious parameters
     *      6. repay the flash loan with the sale proceeds plus the caller's optional debt-token
     *         buffer, or add the caller's optional collateral to the new position
     *      After the flash loan settles, the old GT is transferred back to the caller, any
     *      rounding-dust shares are redeemed to the caller as debt token (reverts if the vault
     *      forbids it within this transaction — dust is wei-level), and any collateral or debt
     *      token left is refunded to the caller.
     * @param market The current market of the GT position
     * @param gtId The ID of the GT token being rolled over
     * @param repayAmt The debt amount to roll (capped to the current debt; pass the full debt
     *        or type(uint128).max for a full rollover)
     * @param additionalAsset The debt token (to cover rollover cost) or the collateral token
     *        (to increase collateral in the new position)
     * @param additionalAmt Amount of `additionalAsset` pulled from the caller; any unused amount
     *        is refunded
     * @param provider The flash loan provider type (MORPHO or AAVE)
     * @param flashLender The Morpho core or Aave v3 pool address to borrow from
     * @param vault The ITermMaxVaultV2 used to source the old market's FT
     * @param ftOrders Vault orders of the old market from which FT is withdrawn
     * @param ftAmounts FT amount withdrawn from each corresponding order; the sum must equal
     *        the effective `repayAmt`
     * @param rolloverData abi.encode(routerV2, removedCollateral, newMarket, maxDebtAmt, swapFtPath)
     *  - routerV2(address): the TermMaxRouterV2 the borrow flow is delegated to
     *  - removedCollateral(uint256): ERC20 collateral amount moved from the old position, also
     *        used as the exact collateral input of the new position; the leftover old position
     *        must stay healthy (checked by the GT)
     *  - newMarket(ITermMaxMarket): the market of the new position
     *  - maxDebtAmt(uint128): debt of the new position
     *  - swapFtPath(SwapPath): new ft -> debt token, built by the backend:
     *        - `recipient` must be THIS contract (sale proceeds repay the flash loan)
     *        - exact-output style with `TermMaxSwapData.refundAddress` = routerV2, so the
     *          unsold FT stays in routerV2 and automatically repays (reduces) the new debt
     * @return newGtId The ID of the newly created GT token in the new market
     */
    function flashRolloverGt(
        ITermMaxMarket market,
        uint256 gtId,
        uint128 repayAmt,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        FlashLoanProvider provider,
        address flashLender,
        ITermMaxVaultV2 vault,
        address[] memory ftOrders,
        uint256[] memory ftAmounts,
        bytes memory rolloverData
    ) external returns (uint256 newGtId);

    /**
     * @notice Roll a floating rate Aave / Morpho borrow position over into a TermMax fixed
     *         rate position, fully or partially, without any upfront capital
     * @notice Applicable scenario: the caller borrows `debtToken` against `collateral` on Aave
     *         V3 or Morpho Blue and wants the same exposure at a TermMax fixed rate. The third
     *         party market must be quoted in the SAME token pair as `newMarket`
     * @notice The debt token is flash borrowed from the very protocol the position lives in —
     *         an Aave position flash borrows from that Aave pool, a Morpho position from that
     *         Morpho core — so there is no separate flash lender to pass in or to trust
     * @dev The whole flow runs inside a flash loan of `flashAmt` debt token, and that loan IS the
     *      repayment budget — nothing about the third party position is read before taking it:
     *      1. flash borrow `flashAmt` of the debt token, which the caller sizes at or above the
     *         debt it wants to roll
     *      2. apply `delegationData` if provided (aToken permit / Morpho authorization), both
     *         are required to be signed by the caller in favour of this router
     *      3. repay as much of the caller's third party debt as the loan covers, never a wei
     *         more: Aave caps the repayment at what the position owes, and the Morpho repayment
     *         burns borrow shares capped at the ones the position holds, so a loan that covers
     *         the debt closes it without leaving dust debt behind
     *      4. move the collateral here: Aave has no withdraw-on-behalf, so the caller's aTokens
     *         are pulled with the router's aToken allowance and burnt for the underlying; Morpho
     *         collateral is withdrawn on behalf of the caller. Both protocols check the leftover
     *         position stays healthy
     *      5. call `routerV2.borrowTokenFromCollateral` — issues the new ft against every wei of
     *         collateral held here and sells it via `swapFtPath` for the debt token amount the
     *         caller quoted. RouterV2 enforces its own market and adapter whitelists, the new gt
     *         recipient is enforced to this contract and forwarded to the caller, so it can not
     *         be hijacked by malicious parameters
     *      6. the lender pulls the repayment, and everything it does not need — the part of the
     *         loan the debt did not consume, the caller's debt token buffer, a sale quoted above
     *         the cost — is put straight back into the new position as a repayment, capped at its
     *         debt. Nothing is refunded and no allowance is revoked afterwards: by construction
     *         this contract holds no token and grants no allowance once the loan settles
     * @dev Security: the position owner is always `_msgSender()`, never a parameter, so an
     *      existing aToken allowance or Morpho authorization can only ever be used by its own
     *      owner. The flash loan callback additionally verifies that its payload is exactly the
     *      payload this contract encoded for this call, so a hostile lending pool can not
     *      re-enter the callback with a forged position owner
     * @dev Requires, before or within this transaction (see `delegationData`):
     *  - AAVE: the caller approves this router on the collateral reserve's aToken. Only
     *    variable rate debt is supported (Aave V3 stable rate borrowing is deprecated)
     *  - MORPHO: the caller authorizes this router via `morpho.setAuthorization`
     * @param newMarket The TermMax market the position is rolled over into
     * @param flashAmt The debt token amount to flash borrow, which doubles as the repayment
     *        budget: size it at or above what closing the position costs to close it, or below
     *        that to roll only part of the debt over. What the repayment does not consume is not
     *        lost, it goes back into the new position as a repayment
     * @dev Sizing a full rollover: the cost of closing is what the position owes NOW, which is
     *      more than what was borrowed — Aave accrues interest per second, and a Morpho position
     *      costs `SharesMathLib.toAssetsUp(borrowShares)`, at least a wei above the amount that
     *      was borrowed. An underfunded loan does not silently roll less than intended: taking
     *      out all of the collateral against the debt it leaves behind is unhealthy, so the
     *      unwind reverts
     * @param collateralAmt The collateral to move out of the third party position.
     *        type(uint256).max moves all of it — for Aave the caller's whole aToken balance of
     *        the collateral reserve; any other amount above that reverts
     * @param additionalAsset The debt token (to cover rollover cost) or the collateral token
     *        (to increase collateral in the new position)
     * @param additionalAmt Amount of `additionalAsset` pulled from the caller; any unused amount
     *        is refunded
     * @param protocol The third party protocol holding the position, which is also where the
     *        debt token is flash borrowed from (MORPHO or AAVE)
     * @param lendingPool The Morpho core / Aave v3 pool address
     * @param positionData The protocol specific handle of the position being rolled over
     *  - AAVE: unused, the reserves are keyed by the token pair of `newMarket`; pass empty bytes
     *  - MORPHO: abi.encode(Id marketId), whose loan token and collateral token must be the
     *        token pair of `newMarket`
     * @param delegationData Optional one-transaction delegation, empty when the caller already
     *        delegated. Either way the signature must be signed by the caller and delegate to
     *        this router, both are checked on-chain
     *  - AAVE: abi.encode(value, deadline, v, r, s), an EIP-2612 permit of the collateral aToken
     *        letting the router pull `value` aTokens from the caller
     *  - MORPHO: abi.encode(Authorization, Signature) for `setAuthorizationWithSig`, letting the
     *        router manage the caller's Morpho positions
     * @param rolloverData abi.encode(routerV2, maxDebtAmt, swapFtPath)
     *  - routerV2(address): the TermMaxRouterV2 the issue-and-sell flow is delegated to
     *  - maxDebtAmt(uint128): debt of the new TermMax position, the unsold ft repays the excess
     *  - swapFtPath(SwapPath): new ft -> debt token, built by the backend:
     *        - `recipient` must be THIS contract (sale proceeds repay the flash loan)
     *        - exact-output style: the amount it sells for has to cover `flashAmt` plus the flash
     *          loan fee, and quoting it above that costs nothing — the excess repays the new
     *          position instead of being refunded
     *        - `TermMaxSwapData.refundAddress` = routerV2, so the unsold ft stays in routerV2 and
     *          automatically repays (reduces) the new debt
     * @return newGtId The ID of the newly created GT token in `newMarket`
     */
    function rolloverFromLendingProtocol(
        ITermMaxMarket newMarket,
        uint256 flashAmt,
        uint256 collateralAmt,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        FlashLoanProvider protocol,
        address lendingPool,
        bytes memory positionData,
        bytes memory delegationData,
        bytes memory rolloverData
    ) external returns (uint256 newGtId);
}
