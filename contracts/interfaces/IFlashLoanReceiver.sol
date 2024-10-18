// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFlashLoanReceiver {
    /// @notice Execute operation to be called in flash loan function
    /// @dev Add your operations logic here
    /// @param sender Address of the sender
    /// @param asset Asset to be flash loaned
    /// @param amount Amount to be flash loaned
    /// @param data Data to be passed to the receiver
    function executeOperation(
        address sender,
        IERC20 asset,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success);
}
