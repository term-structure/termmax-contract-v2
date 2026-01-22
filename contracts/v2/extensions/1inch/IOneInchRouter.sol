// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOneInchRouter {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    /**
     * @notice Performs a swap, delegating all calls encoded in `data` to `executor`. See tests for usage examples.
     * @dev Router keeps 1 wei of every token on the contract balance for gas optimisations reasons.
     *      This affects first swap of every token by leaving 1 wei on the contract.
     * @param executor Aggregation executor that executes calls described in `data`.
     * @param desc Swap description.
     * @param data Encoded calls that `caller` should execute in between of swaps.
     * @return returnAmount Resulting token amount.
     * @return spentAmount Source token amount.
     */
    function swap(address executor, SwapDescription memory desc, bytes memory data)
        external
        payable
        returns (uint256 returnAmount, uint256 spentAmount);
}
