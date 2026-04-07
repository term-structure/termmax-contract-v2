// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStableERC4626For4626} from "../tokens/IStableERC4626For4626.sol";
import {StakingBuffer} from "../tokens/StakingBuffer.sol";

contract MockStableERC4626For4626 is ERC20, IStableERC4626For4626 {
    bool public updateCalled;
    bool public withdrawCalled;

    uint256 public lastAdditionalReserves;
    uint256 public lastMinimumBuffer;
    uint256 public lastMaximumBuffer;
    uint256 public lastBuffer;

    address public lastAsset;
    address public lastTo;
    uint256 public lastAmount;

    constructor() ERC20("MockStableERC4626For4626", "mS4626") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function updateBufferConfigAndAddReserves(
        uint256 additionalReserves,
        StakingBuffer.BufferConfig memory bufferConfig_
    ) external {
        updateCalled = true;
        lastAdditionalReserves = additionalReserves;
        lastMinimumBuffer = bufferConfig_.minimumBuffer;
        lastMaximumBuffer = bufferConfig_.maximumBuffer;
        lastBuffer = bufferConfig_.buffer;
    }

    function withdrawIncomeAssets(address asset, address to, uint256 amount) external {
        withdrawCalled = true;
        lastAsset = asset;
        lastTo = to;
        lastAmount = amount;
    }
}
