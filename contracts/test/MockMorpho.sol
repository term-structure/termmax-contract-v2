pragma solidity ^0.8.0;

import {TransferUtils, IERC20} from "contracts/lib/TransferUtils.sol";
import {IMintableERC20} from "contracts/tokens/MintableERC20.sol";
import {IFlashLoanMorpho, IMorphoFlashLoanCallback} from "contracts/extensions/IFlashLoanMorpho.sol";

contract MockMorpho is IFlashLoanMorpho {
    using TransferUtils for IERC20;

    function flashLoan(address asset, uint256 amount, bytes calldata params) external override {
        IMintableERC20(asset).mint(msg.sender, amount);
        IMorphoFlashLoanCallback(msg.sender).onMorphoFlashLoan(amount, params);
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
    }
}
