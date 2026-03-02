// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBeefyVaultV7 {
    function want() external view returns (address);
    function withdraw(uint256 _shares) external;
    function getPricePerFullShare() external view returns (uint256);
}
