// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {ITermMaxVaultV2} from "../vault/ITermMaxVaultV2.sol";

/// @notice External flash loan liquidity source used by `flashRolloverGt`
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
}
