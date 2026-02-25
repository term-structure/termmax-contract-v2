// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TermMaxBeefySharePriceFeedAdapter} from
    "contracts/v2/oracle/adapters/beefy/TermMaxBeefySharePriceFeedAdapter.sol";
import {IBeefyVaultV7} from "contracts/v2/oracle/adapters/beefy/IBeefyVaultV7.sol";
import {IKodiakIsland} from "contracts/v2/oracle/adapters/beefy/IKodiakIsland.sol";
import {AggregatorV3Interface} from "contracts/v2/oracle/priceFeeds/ITermMaxPriceFeed.sol";

contract ForkBeefySharePriceFeedAdapterTest is Test {
    using Math for *;
    using SafeCast for *;

    // from testShareReader
    address internal constant BEEFY_VAULT = 0xAf92a4C7FCBc0Af09CfFf66d36C615fB40Ac1eEE;
    // user provided price feeds
    address internal constant TOKEN0_PRICE_FEED = 0xbbF121624c3b85C929Ac83872bf6c86b0976A55e;
    address internal constant TOKEN1_PRICE_FEED = 0x2D4f3199a80b848F3d094745F3Bbd4224892654e;

    uint256 internal constant FORK_BLOCK = 17114472;
    uint256 internal constant OUTPUT_DECIMALS = 1e8;

    string internal MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    TermMaxBeefySharePriceFeedAdapter public adapter;

    function setUp() public {
        uint256 forkId = vm.createFork(MAINNET_RPC_URL, FORK_BLOCK);
        vm.selectFork(forkId);

        adapter = new TermMaxBeefySharePriceFeedAdapter(BEEFY_VAULT, TOKEN0_PRICE_FEED, TOKEN1_PRICE_FEED);
    }

    function testLatestRoundDataOutput() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();

        assertGt(answer, 0, "share price should be positive");
        assertGt(startedAt, 0, "startedAt should be positive");
        assertGt(updatedAt, 0, "updatedAt should be positive");

        console.log("roundId:", roundId);
        console.log("answeredInRound:", answeredInRound);
        console.log("share price (8 decimals):", uint256(answer));
        console.log("share price (human):", uint256(answer) / OUTPUT_DECIMALS);
        console.log("startedAt:", startedAt);
        console.log("updatedAt:", updatedAt);
    }

    function testLatestRoundDataMatchesManualCalculation() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();

        IBeefyVaultV7 vault = IBeefyVaultV7(BEEFY_VAULT);
        IKodiakIsland lp = IKodiakIsland(vault.want());

        (uint80 roundId0, int256 price0, uint256 startedAt0, uint256 updatedAt0, uint80 answeredInRound0) =
            AggregatorV3Interface(TOKEN0_PRICE_FEED).latestRoundData();
        (, int256 price1, uint256 startedAt1, uint256 updatedAt1,) =
            AggregatorV3Interface(TOKEN1_PRICE_FEED).latestRoundData();

        assertGt(price0, 0, "token0 feed should be positive");
        assertGt(price1, 0, "token1 feed should be positive");

        uint256 ppfs = vault.getPricePerFullShare();
        uint256 lpAmountForOneShare = ppfs;

        uint256 supply = lp.totalSupply();
        (uint256 total0, uint256 total1) = lp.getUnderlyingBalances();

        uint256 token0Amount = total0.mulDiv(lpAmountForOneShare, supply);
        uint256 token1Amount = total1.mulDiv(lpAmountForOneShare, supply);

        address token0 = lp.token0();
        address token1 = lp.token1();

        uint256 token0Denominator =
            10 ** (IERC20Metadata(token0).decimals() + AggregatorV3Interface(TOKEN0_PRICE_FEED).decimals());
        uint256 token1Denominator =
            10 ** (IERC20Metadata(token1).decimals() + AggregatorV3Interface(TOKEN1_PRICE_FEED).decimals());

        uint256 token0Value = token0Amount.mulDiv(price0.toUint256() * OUTPUT_DECIMALS, token0Denominator);
        uint256 token1Value = token1Amount.mulDiv(price1.toUint256() * OUTPUT_DECIMALS, token1Denominator);
        uint256 expected = token0Value + token1Value;

        assertApproxEqAbs(
            uint256(answer), expected, expected / 1000, "adapter price should be within 1% of manual calculation"
        );
        assertEq(roundId, roundId0, "roundId should follow token0 feed");
        assertEq(answeredInRound, answeredInRound0, "answeredInRound should follow token0 feed");
        assertEq(startedAt, startedAt0.min(startedAt1), "startedAt should be min of two feeds");
        assertEq(updatedAt, updatedAt0.min(updatedAt1), "updatedAt should be min of two feeds");
    }

    function testGetRoundDataReverts() public {
        vm.expectRevert(TermMaxBeefySharePriceFeedAdapter.GetRoundDataNotSupported.selector);
        adapter.getRoundData(1);
    }

    function testOneshareRealPrice() public view {
        IBeefyVaultV7 vault = IBeefyVaultV7(BEEFY_VAULT);
        IKodiakIsland lp = IKodiakIsland(vault.want());

        uint256 ppfs = vault.getPricePerFullShare();
        uint256 lpAmountForOneShare = ppfs;

        uint256 supply = lp.totalSupply();
        (uint256 total0, uint256 total1) = lp.getUnderlyingBalances();

        uint256 token0Amount = total0.mulDiv(lpAmountForOneShare, supply);
        uint256 token1Amount = total1.mulDiv(lpAmountForOneShare, supply);

        console.log("Token0 amount for 1 share:", token0Amount);
        console.log("Token1 amount for 1 share:", token1Amount);
    }

    function testShareReader() public {
        address vault = BEEFY_VAULT;
        address shareHolder = 0x611d3714B1BC0F3eD65510970e080aa9AA6E8009;
        uint256 shareBalance = IERC20(vault).balanceOf(shareHolder);
        uint256 shareAmount = 1e18; // 1 share with 18 decimals

        address lp_pool = IBeefyVaultV7(vault).want();
        (uint256 lpAmount, uint256 token0Amount, uint256 token1Amount) =
            BeefyLPUnderlyingReader.quoteForShareAmount(vault, shareAmount);
        console.log("LP amount for share amount:", lpAmount);
        console.log("Token0 amount for share amount:", token0Amount);
        console.log("Token1 amount for share amount:", token1Amount);
        uint256 lpBalanceBefore = IERC20(lp_pool).balanceOf(shareHolder);
        vm.prank(shareHolder);
        IBeefyVaultV7(vault).withdraw(shareAmount);
        assertEq(
            IERC20(vault).balanceOf(shareHolder),
            shareBalance - shareAmount,
            "Share balance should decrease by withdrawn amount"
        );
        assertApproxEqAbs(
            IERC20(lp_pool).balanceOf(shareHolder) - lpBalanceBefore,
            lpAmount,
            1e6,
            "LP balance change should be close to quoted LP amount"
        );
        // burn lps to get underlying amounts and verify
        address token0 = IKodiakIsland(lp_pool).token0();
        address token1 = IKodiakIsland(lp_pool).token1();
        uint256 amount0BalanceBefore = IERC20(token0).balanceOf(shareHolder);
        uint256 amount1BalanceBefore = IERC20(token1).balanceOf(shareHolder);
        vm.prank(shareHolder);
        (uint256 burn0, uint256 burn1,) = IKodiakIsland(lp_pool).burn(lpAmount, shareHolder);
        uint256 amount0BalanceAfter = IERC20(token0).balanceOf(shareHolder);
        uint256 amount1BalanceAfter = IERC20(token1).balanceOf(shareHolder);
        assertEq(amount0BalanceAfter - amount0BalanceBefore, burn0, "Token0 balance change should match burn output");
        assertEq(amount1BalanceAfter - amount1BalanceBefore, burn1, "Token1 balance change should match burn output");
        console.log("Actual token0 received from burning:", burn0);
        console.log("Actual token1 received from burning:", burn1);
        console.log("Quoted token0 amount for share amount:", token0Amount);
        console.log("Quoted token1 amount for share amount:", token1Amount);
        // allow some slippage between quoted and actual amounts due to price changes, but they should be in the same ballpark
        assertApproxEqAbs(burn0, token0Amount, token0Amount / 100, "Actual token0 should be within 1% of quoted amount");
        assertApproxEqAbs(burn1, token1Amount, token1Amount / 100, "Actual token1 should be within 1% of quoted amount");
    }
}

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
