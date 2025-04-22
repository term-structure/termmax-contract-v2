// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TransferUtils, IERC20} from "contracts/lib/TransferUtils.sol";

abstract contract StakingBuffer {
    using TransferUtils for IERC20;

    error InvalidBuffer(uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer);

    struct BufferConfig {
        uint256 minimumBuffer;
        uint256 maximumBuffer;
        uint256 buffer;
    }

    function _depositWithBuffer(address assertAddr, uint256 amount) internal {
        uint256 assetBalance = IERC20(assertAddr).balanceOf(address(this));
        BufferConfig memory bufferConfig = _bufferConfig(assertAddr);
        if (assetBalance + amount > bufferConfig.maximumBuffer) {
            _depositToPool(assertAddr, assetBalance + amount - bufferConfig.buffer);
        }
    }

    function _withdrawWithBuffer(address assertAddr, uint256 amount) internal {
        uint256 assetBalance = IERC20(assertAddr).balanceOf(address(this));
        BufferConfig memory bufferConfig = _bufferConfig(assertAddr);
        if (assetBalance < amount || assetBalance - amount < bufferConfig.minimumBuffer) {
            _withdrawFromPool(assertAddr, bufferConfig.buffer + amount - assetBalance);
        }
    }

    function _bufferConfig(address assertAddr) internal view virtual returns (BufferConfig memory);

    function _depositToPool(address assertAddr, uint256 amount) internal virtual;

    function _withdrawFromPool(address assertAddr, uint256 amount) internal virtual;
}
