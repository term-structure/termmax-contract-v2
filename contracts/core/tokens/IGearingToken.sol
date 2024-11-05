// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Term Max Gearing token interface
 * @author Term Structure Labs
 */
interface IGearingToken is IERC721 {
    /// @notice Data of Gearing Token's configuturation
    struct GtConfig {
        /// @notice The market's address
        address market;
        /// @notice The address of collateral token
        address collateral;
        /// @notice The underlying(debt) token
        IERC20Metadata underlying;
        /// @notice The bond token
        IERC20 ft;
        /// @notice The treasurer's address, which will receive protocol reward while liquidation
        address treasurer;
        /// @notice The price feed of underlying token
        AggregatorV3Interface underlyingOracle;
        /// @notice The unix time of maturity date
        uint64 maturity;
        /// @notice The debt liquidation threshold
        ///         If the loan to collateral is greater than or equal to this value,
        ///         it will be liquidated
        ///         i.e. 0.9e8 means debt value is the 90% of collateral value
        uint32 liquidationLtv;
        /// @notice Maximum loan to collateral when borrowing
        ///         i.e. 0.85e8 means debt value is the 85% of collateral value
        uint32 maxLtv;
        /// @notice The flag to indicate debt is liquidatable or not
        /// @dev    If liquidatable is false, the collateral can only be delivered after maturity
        bool liquidatable;
    }

    /// @notice Set the treasurer address
    /// @param treasurer New address of treasurer
    /// @dev Only the market can call this function
    function setTreasurer(address treasurer) external;

    /// @notice Return the configuration of Gearing Token
    function getGtConfig() external view returns (GtConfig memory);

    /// @notice Return the flag to indicate debt is liquidatable or not
    function liquidatable() external view returns (bool);

    /// @notice Return the market's address
    function marketAddr() external view returns (address);

    /// @notice Mint this token to an address
    /// @param  to The address receiving token
    /// @param  debtAmt The amount of debt, unit by underlying token
    /// @param  collateralData The encoded data of collateral
    /// @return id The id of Gearing Token
    /// @dev Only the market can mint Gearing Token
    function mint(
        address to,
        uint128 debtAmt,
        bytes memory collateralData
    ) external returns (uint256 id);

    /// @notice Return the loan information of Gearing Token
    /// @param  id The id of Gearing Token
    /// @return owner The owner of Gearing Token
    /// @return debtAmt The amount of debt, unit by underlying token
    /// @return ltv The loan to collateral
    /// @return collateralData The encoded data of collateral
    function loanInfo(
        uint256 id
    )
        external
        view
        returns (
            address owner,
            uint128 debtAmt,
            uint128 ltv,
            bytes memory collateralData
        );

    /// @notice Merge multiple Gearing Tokens into one
    /// @param  ids The array of Gearing Tokens to be merged
    /// @return newId The id of new Gearing Token
    function merge(uint256[] memory ids) external returns (uint256 newId);

    /// @notice Repay the debt of Gearing Token.
    ///         If repay amount equals the debt amount, Gearing Token's owner will get his collateral.
    /// @param id The id of Gearing Token
    /// @param repayAmt The amount of debt you want to repay
    /// @param byUnderlying Repay using underlying token or bonds token
    function repay(uint256 id, uint128 repayAmt, bool byUnderlying) external;

    /// @notice Remove collateral from the loan.
    ///         Require the loan to value bigger than maxLtv after this action.
    /// @param id The id of Gearing Token
    /// @param collateralData Collateral data to be removed
    function removeCollateral(uint256 id, bytes memory collateralData) external;

    /// @notice Add collateral to the loan
    /// @param id The id of Gearing Token
    /// @param collateralData Collateral data to be added
    function addCollateral(uint256 id, bytes memory collateralData) external;

    /// @notice Return the liquidation info of the loan
    /// @param  id The id of the G-token
    /// @return isLiquidable Whether the loan is liquidable
    /// @return maxRepayAmt The maximum amount of the debt to be repaid
    function getLiquidationInfo(
        uint256 id
    ) external view returns (bool isLiquidable, uint128 maxRepayAmt);

    /// @notice Liquidate the loan when its ltv bigger than liquidationLtv or expired.
    ///         The ltv can not inscrease after liquidation.
    ///         A maximum of 10% of the repayment amount of collateral is given as a
    ///         reward to the protocol and liquidator,
    ///         The proportion of collateral liquidated will not exceed the debt liquidation ratio.
    /// @param  id The id of the G-token
    /// @param  repayAmt The amount of the debt to be liquidate
    function liquidate(uint256 id, uint128 repayAmt) external;

    /// @notice Deilivery outstanding debts after maturity
    /// @param  proportion The proportion of collateral that should be obtained
    /// @param  to The address receiving collateral token
    /// @dev    Only the market can delivery collateral
    function delivery(
        uint256 proportion,
        address to
    ) external returns (bytes memory deliveryData);
}
