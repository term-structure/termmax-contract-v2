// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface ITermMaxVaultV2 {
    /// @notice Returns the apr based on accreting principal
    function apy() external view returns (uint256);
}
