// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFlashLoanAave, IAaveFlashLoanCallback} from "contracts/extensions/IFlashLoanAave.sol";
import {TransferUtils, IERC20} from "contracts/lib/TransferUtils.sol";
import {IMintableERC20} from "contracts/tokens/MintableERC20.sol";

contract MockAave is IFlashLoanAave {
    using TransferUtils for IERC20;

    function flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes calldata params, uint16)
        public
    {
        IMintableERC20(asset).mint(receiverAddress, amount);
        uint256 premium = amount * FLASHLOAN_PREMIUM_TOTAL() / 10000;
        IAaveFlashLoanCallback(msg.sender).executeOperation(asset, amount, premium, msg.sender, params);
        IERC20(asset).transferFrom(msg.sender, address(this), amount + premium);
    }

    /**
     * @notice Returns the fee on flash loans
     * @return The flash loan fee, expressed in bps
     */
    function FLASHLOAN_PREMIUM_TOTAL() public view returns (uint128) {
        return 5;
    }
}
