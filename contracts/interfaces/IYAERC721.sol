// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IYAERC721{

    function liquidationThreshHold() external view returns (uint16);

    function marketAddress() external view returns (address);

    /// Amplifier by pt, cToken, aToken and etc. Input collateral to keep the loan is healthy
    function amplifier(uint128 yaInput, uint128 collateralInput) external returns (uint128 netOutput);

    function liquidate(uint256 loanId) external;

    
}