// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "./tokens/IMintableERC20.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {ITermMaxMarket} from "./ITermMaxMarket.sol";
import {MarketConfig, CurveCuts, FeeConfig} from "./storage/TermMaxStorage.sol";

/**
 * @title TermMax Order interface
 * @author Term Structure Labs
 */
interface ITermMaxOrder {
    /// @notice Initialize the token and configuration of the order
    /// @param admin Administrator address for configuring parameters such as transaction fees
    /// @param maker The maker
    /// @param curveCuts The curve cuts
    /// @dev Only factory will call this function once when deploying new market
    function initialize(
        address admin,
        address maker,
        IERC20[3] memory tokens,
        IGearingToken gt,
        CurveCuts memory curveCuts,
        MarketConfig memory marketConfig
    ) external;

    /// @notice Return the configuration
    function curveCuts() external view returns (CurveCuts memory);

    function maker() external view returns (address);

    /// @notice Set the market configuration
    /// @param newCurveCuts New curve cuts
    /// @param newFtReserve New FT reserve amount
    /// @param newXtReserve New XT reserve amount
    /// @param gtId The id of Gearing Token
    function updateOrder(
        CurveCuts memory newCurveCuts,
        uint256 newFtReserve,
        uint256 newXtReserve,
        uint256 gtId
    ) external;

    function updateFeeConfig(FeeConfig memory newFeeConfig) external;

    function feeConfig() external view returns (FeeConfig memory);

    /// @notice Return the token reserves
    function tokenReserves() external view returns (uint256 ftReserve, uint256 xtReserve, uint256 gtId);

    /// @notice Return the tokens in TermMax Market
    /// @return market The market
    function market() external view returns (ITermMaxMarket market);

    /// @notice Return the current apr of the amm order book
    /// @return lendApr Lend APR
    /// @return borrowApr Borrow APR
    function apr() external view returns (uint256 lendApr, uint256 borrowApr);

    /// @notice Buy FT using debtToken token
    /// @param debtTokenAmtIn The number of unterlying tokens input
    /// @param minTokenOut Minimum number of FT token outputs required
    /// @return netOut The actual number of FT tokens received
    function buyFt(uint128 debtTokenAmtIn, uint128 minTokenOut) external returns (uint256 netOut);

    /// @notice Buy XT using debtToken token
    /// @param debtTokenAmtIn The number of unterlying tokens input
    /// @param minTokenOut Minimum number of XT token outputs required
    /// @return netOut The actual number of XT tokens received
    function buyXt(uint128 debtTokenAmtIn, uint128 minTokenOut) external returns (uint256 netOut);

    /// @notice Sell FT to get debtToken token
    /// @param ftAmtIn The number of FT tokens input
    /// @param minUnderlyingOut Minimum number of debtToken token outputs required
    /// @return netOut The actual number of debtToken tokens received
    function sellFt(uint128 ftAmtIn, uint128 minUnderlyingOut) external returns (uint256 netOut);

    /// @notice Sell XT to get debtToken token
    /// @param xtAmtIn The number of XT tokens input
    /// @param minUnderlyingOut Minimum number of debtToken token outputs required
    /// @return netOut The actual number of debtToken tokens received
    function sellXt(uint128 xtAmtIn, uint128 minUnderlyingOut) external returns (uint256 netOut);

    /// @notice Suspension of market trading
    function pause() external;

    /// @notice Open Market Trading
    function unpause() external;
}
