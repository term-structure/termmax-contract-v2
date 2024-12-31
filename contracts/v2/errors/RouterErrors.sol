// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface RouterErrors {
    /// @notice Error for calling the market is not whitelisted
    error MarketNotWhitelisted(address market);
    /// @notice Error for calling the gt is not whitelisted
    error GtNotWhitelisted(address gt);
    /// @notice Error for calling the adapter is not whitelisted
    error AdapterNotWhitelisted(address adapter);
    /// @notice Error for the final loan to collateral is bigger than expected
    error LtvBiggerThanExpected(uint128 expectedLtv, uint128 actualLtv);
    /// @notice Error for approving token failed when swapping
    error ApproveTokenFailWhenSwap(address token, bytes revertData);
    /// @notice Error for failed swapping
    error SwapFailed(address adapter, bytes revertData);
    /// @notice Error for the token output is less than expected
    error InsufficientTokenOut(address token, uint256 expectedTokenOut, uint256 actualTokenOut);
}
