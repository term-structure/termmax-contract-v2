// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IGearingToken, IGearingTokenV2, IERC20, IFlashRepayer} from "../tokens/AbstractGearingTokenV2.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";

contract MockFlashRepayer is IFlashRepayer, IERC721Receiver {
    IGearingToken gt;

    constructor(IGearingToken gt_) {
        gt = gt_;
    }

    function flashRepay(uint256 id, uint128 repayAmt, bool byUnderlying, bytes calldata removedCollateral) external {
        gt.safeTransferFrom(msg.sender, address(this), id, "");
        bool repayAll = IGearingTokenV2(address(gt)).flashRepay(id, repayAmt, byUnderlying, removedCollateral, "");
        if (!repayAll) {
            gt.safeTransferFrom(address(this), msg.sender, id, "");
        }
    }

    function executeOperation(IERC20 repayToken, uint128 debtAmt, address, bytes memory, bytes calldata)
        external
        override
    {
        repayToken.approve(address(gt), debtAmt);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
