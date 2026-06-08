// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StakingBuffer, IERC20} from "./StakingBuffer.sol";

interface IStableERC4626For4626 is IERC20 {
    function updateBufferConfigAndAddReserves(
        uint256 additionalReserves,
        StakingBuffer.BufferConfig memory bufferConfig_
    ) external;

    function withdrawIncomeAssets(address asset, address to, uint256 amount) external;
}
