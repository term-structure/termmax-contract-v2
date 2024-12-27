// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "./tokens/IMintableERC20.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {MarketConfig} from "./storage/TermMaxStorage.sol";

/**
 * @title TermMax Market interface
 * @author Term Structure Labs
 */
interface ITermMaxMarket {
    /// @notice Initialize the token and configuration of the market
    /// @param admin Administrator address for configuring parameters such as transaction fees
    /// @param collateral_ Collateral token
    /// @param underlying_ Underlying Token(debt)
    /// @param ft_ TermMax FT
    /// @param xt_ TermMax XT
    /// @param gt_ TermMax Gearing Token
    /// @param config_ Configuration of market
    /// @dev Only factory will call this function once when deploying new market
    function initialize(
        address admin,
        address collateral_,
        IERC20 underlying_,
        IMintableERC20 ft_,
        IMintableERC20 xt_,
        IGearingToken gt_,
        MarketConfig memory config_
    ) external;

    /// @notice Return the configuration
    function config() external view returns (MarketConfig memory);

    /// @notice Set the market configuration
    function updateMarketConfig(MarketConfig calldata newConfig) external;

    /// @notice Return the tokens in TermMax Market
    /// @return ft Fixed-rate Token(bond token). Earning Fixed Income with High Certainty
    /// @return xt Intermediary Token for Collateralization and Leveragin
    /// @return gt Gearing Token
    /// @return collateral Collateral token
    /// @return underlying Underlying Token(debt)
    function tokens()
        external
        view
        returns (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, address collateral, IERC20 underlying);

    /// @notice Mint FT and XT tokens by underlying token.
    ///         No price slippage or handling fees.
    /// @param underlyingAmt Amount of underlying token want to lock
    function mint(address recipient, uint256 underlyingAmt) external;

    /// @notice Burn FT and XT to get underlying token.
    ///         No price slippage or handling fees.
    /// @param underlyingAmt Amount of underlying token want to get
    function burn(address recipient, uint256 underlyingAmt) external;

    /// @notice Using collateral to issue FT tokens.
    ///         Caller will get FT(bond) tokens equal to the debt amount subtract issue fee
    /// @param debt The amount of debt, unit by underlying token
    /// @param collateralData The encoded data of collateral
    /// @return gtId The id of Gearing Token
    ///
    function issueFt(
        address recipient,
        uint128 debt,
        bytes calldata collateralData
    ) external returns (uint256 gtId, uint128 ftOutAmt);

    /// @notice Using collateral to issue FT tokens.
    ///         Caller will get FT(bond) tokens equal to the debt amount subtract issue fee
    /// @param recipient Who will receive Gearing Token
    /// @param debt The amount of debt, unit by underlying token
    /// @param gtId The id of Gearing Token
    /// @return ftOutAmt The amount of FT issued
    ///
    function issueFtByExistedGt(address recipient, uint128 debt, uint gtId) external returns (uint128 ftOutAmt);

    /// @notice Flash loan underlying token for leverage
    /// @param recipient Who will receive Gearing Token
    /// @param xtAmt The amount of XT token.
    ///              The caller will receive an equal amount of underlying token by flash loan.
    /// @param callbackData The data of flash loan callback
    /// @return gtId The id of Gearing Token
    function leverageByXt(
        address recipient,
        uint128 xtAmt,
        bytes calldata callbackData
    ) external returns (uint256 gtId);

    /// @notice Redeem underlying tokens after maturity
    /// @param ftAmount The amount of FT want to redeem
    /// @param recipient Who will receive the underlying tokens
    function redeem(uint256 ftAmount, address recipient) external;

    /// @notice Set the configuration of Gearing Token
    function updateGtConfig(bytes memory configData) external;
}
