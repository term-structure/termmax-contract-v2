// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IGearingToken, IERC20, IFlashRepayer} from "../core/tokens/AbstractGearingToken.sol";

contract MockFlashRepayer is IFlashRepayer {
    IGearingToken gt;

    constructor(IGearingToken gt_) {
        gt = gt_;
    }

    function flashRepay(uint256 id) external {
        gt.flashRepay(id, abi.encode(msg.sender));
    }

    function executeOperation(
        address owner,
        IERC20 debtToken,
        uint128 debtAmt,
        address collateralToken,
        bytes memory collateralData,
        bytes calldata callbackData
    ) external override {
        assert(owner == abi.decode(callbackData, (address)));
        IERC20(collateralToken).transferFrom(
            owner,
            address(this),
            abi.decode(collateralData, (uint))
        );
        debtToken.approve(address(gt), debtAmt);
    }
}
