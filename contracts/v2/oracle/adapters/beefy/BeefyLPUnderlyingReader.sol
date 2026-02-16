// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IKodiakIsland} from "./IKodiakIsland.sol";
import {IBeefyVaultV7} from "./IBeefyVaultV7.sol";

/// @title BeefyLPUnderlyingReader
/// @notice Utility reader for quoting token0/token1 equivalents for KodiakIsland LP shares.
library BeefyLPUnderlyingReader {
    uint256 internal constant PRICE_DECIMALS = 1e18;

    /// @notice Quote underlying token amounts for an arbitrary LP amount.
    /// @param island KodiakIslandWithRouter (or KodiakIsland) vault address.
    /// @param lpAmount LP amount in smallest unit (wei of LP token).
    /// @return token0Amount token0 amount in smallest unit.
    /// @return token1Amount token1 amount in smallest unit.
    function quoteForLpAmount(address island, uint256 lpAmount)
        internal
        view
        returns (uint256 token0Amount, uint256 token1Amount)
    {
        IKodiakIsland vault = IKodiakIsland(island);

        uint256 supply = vault.totalSupply();
        if (supply == 0) {
            return (0, 0);
        }

        (uint256 total0, uint256 total1) = vault.getUnderlyingBalances();

        token0Amount = Math.mulDiv(total0, lpAmount, supply);
        token1Amount = Math.mulDiv(total1, lpAmount, supply);
    }

    /// @notice Quote underlying token amounts for exactly 1 LP token (1e18 LP wei).
    /// @dev KodiakIsland inherits Solady ERC20, default LP decimals is 18.
    /// @param island KodiakIslandWithRouter (or KodiakIsland) vault address.
    /// @return token0Amount token0 amount for 1 LP, in smallest unit.
    /// @return token1Amount token1 amount for 1 LP, in smallest unit.
    function quoteOneLp(address island) internal view returns (uint256 token0Amount, uint256 token1Amount) {
        return quoteForLpAmount(island, 1e18);
    }

    /// @notice Convenience method returning both values in a struct.
    function quoteOneLpStruct(address island) internal view returns (uint256 token0Amount, uint256 token1Amount) {
        (token0Amount, token1Amount) = quoteForLpAmount(island, 1e18);
    }

    /// @notice Quote LP and underlying token amounts for a Beefy vault share amount.
    /// @dev Assumes want() is a KodiakIsland LP.
    /// @param shareVault BeefyVaultV7 address.
    /// @param shareAmount Beefy share amount in smallest unit.
    /// @return lpAmount want(LP) amount represented by shareAmount.
    /// @return token0Amount token0 amount in smallest unit.
    /// @return token1Amount token1 amount in smallest unit.
    function quoteForShareAmount(address shareVault, uint256 shareAmount)
        internal
        view
        returns (uint256 lpAmount, uint256 token0Amount, uint256 token1Amount)
    {
        IBeefyVaultV7 vault = IBeefyVaultV7(shareVault);

        // Beefy getPricePerFullShare returns want/share with 18 decimals.
        uint256 pricePerFullShare = vault.getPricePerFullShare();
        lpAmount = Math.mulDiv(shareAmount, pricePerFullShare, PRICE_DECIMALS);

        (token0Amount, token1Amount) = quoteForLpAmount(vault.want(), lpAmount);
    }

    /// @notice Quote LP and underlying token amounts for exactly 1 share token (1e18 share wei).
    function quoteOneShare(address shareVault)
        internal
        view
        returns (uint256 lpAmount, uint256 token0Amount, uint256 token1Amount)
    {
        return quoteForShareAmount(shareVault, 1e18);
    }

    /// @notice Convenience method returning share->LP->underlying quote in a struct.
    function quoteForShareAmountStruct(address shareVault, uint256 shareAmount)
        internal
        view
        returns (uint256 lpAmount, uint256 token0Amount, uint256 token1Amount)
    {
        (lpAmount, token0Amount, token1Amount) = quoteForShareAmount(shareVault, shareAmount);
    }
}
