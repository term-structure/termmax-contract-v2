// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IPriceCapAdapter {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
}
