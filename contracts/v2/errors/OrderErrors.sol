// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface OrderErrors {
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

    /// @notice Error for invalid unix time parameters
    error InvalidTime(uint64 openTime, uint64 maturity);
    /// @notice Error for lsf value equals 0 or bigger than 1e8
    error InvalidLsf(uint32 lsf);
    /// @notice Error for the collateral and underlying are the same token
    error CollateralCanNotEqualUnderlyinng();
    /// @notice Error for repeat initialization of market
    error MarketHasBeenInitialized();
    /// @notice Error for it is not the opening trading day yet
    error MarketIsNotOpen();
    /// @notice Error for the maturity day has been reached
    error MarketWasClosed();
    /// @notice Error for provider not whitelisted
    error ProviderNotWhitelisted(address provider);
    /// @notice Error for receiving zero lp token when providing liquidity
    error LpOutputAmtIsZero(uint256 underlyingAmt);
    /// @notice Error for lsf is changed between user post trade request
    error LsfChanged();
    /// @notice Error for apr is less than min apr
    error AprLessThanMinApr(int64 apr, int64 minApr);
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
