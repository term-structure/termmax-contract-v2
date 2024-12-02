// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title The interface of flash repayer
 * @author Term Structure Labs
 */
interface IFlashRepayer {
    /// @notice Execute operation to be called in flash repay function
    /// @dev Add your operations logic here
    /// @param owner The loan's owner
    /// @param repayToken Underlying or FT token
    /// @param debtAmt Amount of debt
    /// @param collateralToken Collateral token
    /// @param collateralData Encoded collateral data
    /// @param callbackData The data of flash repay callback
    function executeOperation(
        address owner,
        IERC20 repayToken,
        uint128 debtAmt,
        address collateralToken,
        bytes memory collateralData,
        bytes calldata callbackData
    ) external;
}
