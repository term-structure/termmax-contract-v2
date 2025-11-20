// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StakingBuffer} from "../v2/tokens/StakingBuffer.sol";

interface ITermMax4626Pool is IERC4626 {
    function totalIncomeAssets() external view returns (uint256);

    function thirdPool() external view returns (IERC4626);

    function bufferConfig() external view returns (StakingBuffer.BufferConfig memory);

    function aToken() external view returns (IERC20);
}
