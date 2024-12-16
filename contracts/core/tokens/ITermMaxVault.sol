// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITermMaxVault is IERC4626 {
    function initialize(
        IERC20 asset_,
        address _owner,
        string memory name_,
        string memory symbol_
    ) external;
}