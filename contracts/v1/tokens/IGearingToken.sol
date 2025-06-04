// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {GtConfig} from "../storage/TermMaxStorage.sol";

/**
 * @title TermMax Gearing token interface
 * @author Term Structure Labs
 */
interface IGearingToken is IERC721Enumerable {
    // @notice Initial function
    /// @param name The token's name
    /// @param symbol The token's symbol
    /// @param config Configuration of GT
    /// @param initalParams The initilization parameters of implementation
    function initialize(string memory name, string memory symbol, GtConfig memory config, bytes memory initalParams)
        external;

    /// @notice Set the treasurer address
    /// @param treasurer New address of treasurer
    /// @dev Only the market can call this function
    function setTreasurer(address treasurer) external;

    /// @notice Set the configuration of Gearing Token
    function updateConfig(bytes memory configData) external;

    /// @notice Return the configuration of Gearing Token
    function getGtConfig() external view returns (GtConfig memory);

    /// @notice Return the flag to indicate debt is liquidatable or not
    function liquidatable() external view returns (bool);

    /// @notice Return the market address
    function marketAddr() external view returns (address);

    /// @notice Mint this token to an address
    /// @param  collateralProvider Who provide collateral token
    /// @param  to The address receiving token
    /// @param  debtAmt The amount of debt, unit by debtToken token
    /// @param  collateralData The encoded data of collateral
    /// @return id The id of Gearing Token
    /// @dev Only the market can mint Gearing Token
    function mint(address collateralProvider, address to, uint128 debtAmt, bytes memory collateralData)
        external
        returns (uint256 id);

    /// @notice Augment the debt of Gearing Token
    /// @param  id The id of Gearing Token
    /// @param  ftAmt The amount of debt, unit by debtToken token
    function augmentDebt(address caller, uint256 id, uint256 ftAmt) external;

    /// @notice Return the loan information of Gearing Token
    /// @param  id The id of Gearing Token
    /// @return owner The owner of Gearing Token
    /// @return debtAmt The amount of debt, unit by debtToken token
    /// @return collateralData The encoded data of collateral
    function loanInfo(uint256 id) external view returns (address owner, uint128 debtAmt, bytes memory collateralData);

    /// @notice Merge multiple Gearing Tokens into one
    /// @param  ids The array of Gearing Tokens to be merged
    /// @return newId The id of new Gearing Token
    function merge(uint256[] memory ids) external returns (uint256 newId);

    /// @notice Repay the debt of Gearing Token.
    ///         If repay amount equals the debt amount, Gearing Token's owner will get his collateral.
    /// @param id The id of Gearing Token
    /// @param repayAmt The amount of debt you want to repay
    /// @param byDebtToken Repay using debtToken token or bonds token
    function repay(uint256 id, uint128 repayAmt, bool byDebtToken) external;

    /// @notice Repay the debt of Gearing Token,
    ///         the collateral will send by flashloan first.
    /// @param id The id of Gearing Token
    /// @param byDebtToken Repay using debtToken token or bonds token
    function flashRepay(uint256 id, bool byDebtToken, bytes calldata callbackData) external;

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
    /// @return ltv The loan to collateral
    /// @return maxRepayAmt The maximum amount of the debt to be repaid
    function getLiquidationInfo(uint256 id)
        external
        view
        returns (bool isLiquidable, uint128 ltv, uint128 maxRepayAmt);

    /// @notice Liquidate the loan when its ltv bigger than liquidationLtv or expired.
    ///         The ltv can not inscrease after liquidation.
    ///         A maximum of 10% of the repayment amount of collateral is given as a
    ///         reward to the protocol and liquidator,
    ///         The proportion of collateral liquidated will not exceed the debt liquidation ratio.
    /// @param  id The id of the G-token
    /// @param  repayAmt The amount of the debt to be liquidate
    /// @param  byDebtToken Repay using debtToken token or bonds token
    function liquidate(uint256 id, uint128 repayAmt, bool byDebtToken) external;

    /// @notice Preview the delivery data
    /// @param  proportion The proportion of collateral that should be obtained
    /// @return deliveryData The delivery data
    function previewDelivery(uint256 proportion) external view returns (bytes memory deliveryData);

    /// @notice Deilivery outstanding debts after maturity
    /// @param  proportion The proportion of collateral that should be obtained
    /// @param  to The address receiving collateral token
    /// @dev    Only the market can delivery collateral
    function delivery(uint256 proportion, address to) external returns (bytes memory deliveryData);

    /// @notice Return the value of collateral in USD with base decimals
    /// @param collateralData encoded collateral data
    /// @return collateralValue collateral's value in USD
    function getCollateralValue(bytes memory collateralData) external view returns (uint256 collateralValue);
}
