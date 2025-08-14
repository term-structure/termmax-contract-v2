// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC4626, IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract MockERC4626 is ERC4626, Pausable {
    constructor(IERC20 asset) ERC4626(asset) ERC20("MockERC4626", "mERC4626") {}

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        if (paused()) {
            return 0; // Return 0 if paused
        }
        return super.previewRedeem(shares);
    }

    function pause() public {
        _pause();
    }

    function unpause() public {
        _unpause();
    }
}
