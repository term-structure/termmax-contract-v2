// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {SwapPath} from "./ITermMaxRouterV2.sol";
import {ITermMaxVaultV2} from "../vault/ITermMaxVaultV2.sol";

/// @notice External flash loan liquidity source used by `flashRolloverGt`
enum FlashLoanProvider {
    MORPHO,
    AAVE
}

/**
 * @title TermMax Router V2.0.2 interface — flash rollover periphery
 * @author Term Structure Labs
 * @notice Rolls a GT position (fully or partially) into a new market using an external
 *         flash loan as temporary vault liquidity. Deployed as a standalone periphery
 *         contract so that TermMaxRouterV2 stays within the EIP-170 bytecode limit.
 */
interface ITermMaxRouterV2_02 {
    /**
     * @notice Rollover a GT position to a new market using an external flash loan as bridging liquidity
     * @dev The whole flow runs inside a Morpho/Aave flash loan of the debt token. The flash loan
     *      amount is computed on-chain as `vault.previewMint(vault.previewWithdraw(repayAmt))` — the
     *      exact assets required to mint just enough shares to redeem `repayAmt` worth of FT:
     *      1. pull the GT from the caller (returned at the end)
     *      2. mint the exact vault shares with the flash-borrowed debt token
     *      3. burn the shares to redeem the old market's FT from a vault order (withdrawFts)
     *      4. `repayAndRemoveCollateral(repayAmt, removedCollateral)` on the old GT in FT —
     *         supports PARTIAL rollover; the GT is never burned and the leftover position
     *         stays intact
     *      5. issue `newDebtAmt` FT on the new market against the removed collateral
     *      6. sell the new FT for the debt token through `sellFtPath` (provided by the backend)
     *      7. repay the flash loan with the sale proceeds plus the caller's `additionalAmt` buffer
     *      After the flash loan settles, the old GT is transferred back to the caller, any
     *      rounding-dust shares are redeemed to the caller as debt token (reverts if the vault
     *      forbids it within this transaction — dust is wei-level), and any debt token left is
     *      refunded to the caller. The old and new market must share the same collateral and
     *      debt token.
     * @param market The current market of the GT position
     * @param gtId The ID of the GT token being rolled over
     * @param repayAmt The debt amount to roll (capped to the current debt; pass the full debt
     *        or type(uint128).max for a full rollover)
     * @param additionalAmt Debt token buffer pulled from the caller to cover the rollover cost
     *        (FT sale discount, issue fee and flash loan premium); the unused part is refunded
     * @param provider The flash loan provider type (MORPHO or AAVE)
     * @param flashLender The Morpho core or Aave v3 pool address to borrow from
     * @param vault The ITermMaxVaultV2 used to source the old market's FT
     * @param ftOrder The vault order the old market's FT is withdrawn from
     * @param rolloverData abi.encode(recipient, removedCollateral, newMarket, newDebtAmt, maxLtv, sellFtPath)
     *  - recipient(address): address receiving the new GT
     *  - removedCollateral(bytes): collateral data moved to the new position, e.g. abi.encode(amount)
     *        for ERC20 collateral; the leftover position must stay healthy (checked by the GT)
     *  - newMarket(ITermMaxMarket): the market of the new position
     *  - newDebtAmt(uint128): debt of the new position
     *  - maxLtv(uint128): max accepted LTV of the new position
     *  - sellFtPath(SwapPath): new ft -> debt token => router
     * @return newGtId The ID of the newly created GT token in the new market
     */
    function flashRolloverGt(
        ITermMaxMarket market,
        uint256 gtId,
        uint128 repayAmt,
        uint256 additionalAmt,
        FlashLoanProvider provider,
        address flashLender,
        ITermMaxVaultV2 vault,
        address ftOrder,
        bytes memory rolloverData
    ) external returns (uint256 newGtId);
}
