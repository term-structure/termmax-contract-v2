// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IStrataVault is IERC4626 {
    function redeem(address token, uint256 shares, address receiver, address owner) external returns (uint256);
}
