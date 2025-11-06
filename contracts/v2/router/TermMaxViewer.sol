// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ITermMaxMarket, IMintableERC20} from "../../v1/ITermMaxMarket.sol";
import {IGearingToken} from "../../v1/tokens/IGearingToken.sol";
import {ITermMaxVault} from "../../interfaces/ITermMaxVault.sol";
import {ITermMax4626Pool} from "../../interfaces/ITermMax4626Pool.sol";

/**
 * @title TermMaxViewer
 * @dev Viewer contract for TermMax protocol
 */
contract TermMaxViewer is UUPSUpgradeable, Ownable2StepUpgradeable {
    using Math for uint256;

    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(address admin) external initializer {
        __UUPSUpgradeable_init_unchained();
        __Ownable_init_unchained(admin);
    }

    function assetsWithERC20Collateral(ITermMaxMarket market, address owner)
        external
        view
        returns (IERC20[4] memory tokens, uint256[4] memory balances, address gtAddr, uint256[] memory gtIds)
    {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateral, IERC20 underlying) = market.tokens();
        tokens[0] = ft;
        tokens[1] = xt;
        tokens[2] = IERC20(collateral);
        tokens[3] = underlying;
        for (uint256 i = 0; i < 4; ++i) {
            balances[i] = tokens[i].balanceOf(owner);
        }
        gtAddr = address(gt);
        uint256 balance = IERC721Enumerable(gtAddr).balanceOf(owner);
        gtIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; ++i) {
            gtIds[i] = IERC721Enumerable(gtAddr).tokenOfOwnerByIndex(owner, i);
        }
    }

    // Calculate the maximum redeemable collateral for bad debt repayment
    function previewDealBadDebt(ITermMaxVault vault, address collateral, address user)
        external
        view
        returns (uint256 maxRedeem, uint256 totalBadDebt, uint256 totalCollateral)
    {
        totalBadDebt = vault.badDebtMapping(collateral);
        if (totalBadDebt == 0) {
            return (0, 0, 0);
        }
        totalCollateral = IERC20(collateral).balanceOf(address(vault));
        maxRedeem = totalCollateral.mulDiv(vault.convertToAssets(vault.balanceOf(user)), totalBadDebt);
    }

    // Get unclaimed rewards across multiple TermMax4626Pools
    function getPoolUnclaimedRewards(ITermMax4626Pool[] memory pools)
        external
        view
        returns (address[] memory asset, uint256[] memory amount)
    {
        asset = new address[](pools.length);
        amount = new uint256[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            ITermMax4626Pool pool = pools[i];
            asset[i] = pool.asset();
            uint256 totalAssets = pool.totalAssets();
            uint256 totalFunds = IERC20(asset[i]).balanceOf(address(pool));
            try pool.aToken() returns (IERC20 aToken) {
                // stable aave pool
                totalFunds += aToken.balanceOf(address(pool));
            } catch {
                // stable 4626 pool
                IERC4626 thirdPool = pool.thirdPool();
                totalFunds += thirdPool.convertToAssets(thirdPool.balanceOf(address(pool)));
            }
            amount[i] = totalFunds > totalAssets ? totalFunds - totalAssets : 0;
        }
    }
}
