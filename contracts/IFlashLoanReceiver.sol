// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title The interface of flash loan in TermMax
 * @author Term Structure Labs
 */
interface IFlashLoanReceiver {
    /// @notice Execute operation to be called in flash loan function
    /// @dev Add your operations logic here
    /// @param gtReceiver Who will receive Gearing Token
    /// @param asset Asset to be flash loaned
    /// @param amount Amount to be flash loaned
    /// @param data Data to be passed to the receiver
    /// @return collateralData Collateral data for borrowing
    function executeOperation(address gtReceiver, IERC20 asset, uint256 amount, bytes calldata data)
        external
        returns (bytes memory collateralData);
}
