// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface OrderErrors {
    error TermIsNotOpen();
    error CantNotSwapToken(IERC20 tokenIn, IERC20 tokenOut);
    error CantSwapSameToken();
    error FeeTooHigh();
    error CantNotIssueFtWithoutGt();
    error InvalidCurveCuts();
    error BorrowIsNotAllowed();
    error LendIsNotAllowed();
    error OnlyMaker();
    error GtNotApproved(uint256 gtId);
    error XtReserveTooHigh();

    /// @notice Error for the actual output value does not match the expected value
    error UnexpectedAmount(uint expectedAmt, uint actualAmt);
    /// @notice Error for redeeming before the liquidation window
    error CanNotRedeemBeforeFinalLiquidationDeadline(uint256 liquidationDeadline);
    /// @notice Error for evacuation mode is not actived
    error EvacuationIsNotActived();
    /// @notice Error for evacuation mode is actived
    error EvacuationIsActived();
    /// @notice Error for not enough excess FT/XT to withdraw
    error NotEnoughFtOrXtToWithdraw();
}
