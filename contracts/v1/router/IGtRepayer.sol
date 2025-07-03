// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
/**
 * @title TermMax Repayer interface
 * @author Term Structure Labs
 * @notice Interface for the TermMax Gt Repayer contract
 */

interface IGtRepayer {
    /**
     * @notice Repays a GT in a TermMax market
     * @param market The TermMax market to repay in
     * @param gtId The ID of the GT to repay
     * @param maxRepayAmt Maximum amount of tokens to repay
     * @param byDebtToken Whether to repay using debt tokens
     * @return repayAmt The actual amount repaid
     */
    function repayGt(ITermMaxMarket market, uint256 gtId, uint128 maxRepayAmt, bool byDebtToken)
        external
        returns (uint128 repayAmt);
}
