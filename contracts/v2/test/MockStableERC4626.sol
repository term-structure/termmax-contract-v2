// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC4626, IERC20, ERC20, Math} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract MockStableERC4626 is ERC4626 {
    constructor(IERC20 asset) ERC4626(asset) ERC20("MockStableERC4626", "mERC4626") {}

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding) internal view virtual override returns (uint256) {
        return assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding) internal view virtual override returns (uint256) {
        return shares;
    }
}
