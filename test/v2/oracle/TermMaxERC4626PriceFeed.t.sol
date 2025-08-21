// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TermMaxERC4626PriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxERC4626PriceFeed.sol";
import {MockPriceFeedV2} from "contracts/v2/test/MockPriceFeedV2.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {console} from "forge-std/console.sol";

// A small adapter mock that extends MockPriceFeedV2 but also exposes asset()
// The real TermMaxERC4626PriceFeed constructor calls IERC4626(_underlyingPriceFeed).asset(),
// so this mock provides an asset() function returning the underlying token address to make the constructor succeed.
contract MockAggWithAsset is MockPriceFeedV2 {
    address private _asset;

    constructor(address admin, address asset_) MockPriceFeedV2(admin) {
        _asset = asset_;
    }

    // Expose an ERC4626-like asset() function so constructor's call succeeds
    function asset() external view returns (address) {
        return _asset;
    }
}

// Custom ERC4626 mock that allows overriding shares (vault) decimals.
contract MockERC4626WithDecimals is ERC4626 {
    uint8 private _decimalsOverride;

    // Inherit only ERC4626; call ERC20 constructor for name/symbol to set ERC20 storage.
    constructor(IERC20Metadata asset_, uint8 decimals_) ERC4626(asset_) ERC20("MockVault", "mV") {
        _decimalsOverride = decimals_;
    }

    // Override decimals for the ERC20 (shares) to simulate vault share decimals
    function decimals() public view virtual override returns (uint8) {
        return _decimalsOverride;
    }

    // Expose deposit helper for tests
    function mintSharesTo(address to, uint256 assets) external returns (uint256) {
        // deposit assets into vault and mint shares to `to` (use deposit from ERC4626)
        // caller must have approved this contract for `assets` beforehand
        return super.deposit(assets, to);
    }
}

contract TermMaxERC4626PriceFeedTest is Test {
    function testUnderlyingAndVaultDifferentDecimals_case1(uint128 depositAmount) public {
        // underlying has 6 decimals (e.g., USDC), vault shares have 18 decimals
        MockERC20 underlying = new MockERC20("USDC", "USDC", 6);
        MockERC4626WithDecimals vault = new MockERC4626WithDecimals(IERC20Metadata(address(underlying)), 18);
        // Mint some USDC to the vault
        underlying.mint(address(this), depositAmount);
        underlying.approve(address(vault), depositAmount);
        // Deposit USDC into the vault to mint shares
        vault.deposit(depositAmount, address(this));

        // Deploy a mock aggregator that also exposes asset() and set its round data
        MockAggWithAsset agg = new MockAggWithAsset(address(this), address(underlying));
        // Set round data: answer = 2 USD (2 * 10^8), decimals = 8 inside MockPriceFeedV2 by default
        MockPriceFeedV2.RoundData memory rd = MockPriceFeedV2.RoundData({
            roundId: 1,
            answer: int256(2 * 10 ** 8),
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });
        agg.updateRoundData(rd);

        // Deploy the TermMaxERC4626PriceFeed with the mock aggregator and the vault
        TermMaxERC4626PriceFeed priceFeed = new TermMaxERC4626PriceFeed(address(agg), address(vault));

        (, int256 feedAnswer,,,) = priceFeed.latestRoundData();

        // Compute expected value per implementation:
        // vaultDenominator = 10 ** vaultDecimals
        uint256 vaultDenominator = 10 ** uint256(vault.decimals());
        // vaultAnswer = convertToAssets(vaultDenominator) (initially 1:1)
        uint256 vaultAnswer = vault.convertToAssets(vaultDenominator);
        // priceDenominator = 10 ** (assetPriceFeed.decimals() + underlyingDecimals)
        uint8 aggDecimals = agg.decimals();
        uint8 underlyingDecimals = underlying.decimals();
        uint256 priceDenominator = 10 ** uint256(aggDecimals + underlyingDecimals);
        uint256 PRICE_DECIMALS = 10 ** 8;

        uint256 aggAnswer = uint256(2 * 10 ** 8);
        uint256 expected = (aggAnswer * vaultAnswer * PRICE_DECIMALS) / priceDenominator;
        assertEq(feedAnswer, int256(expected));
        // check answer is around 2 USD
        assertApproxEqAbs(uint256(feedAnswer), expected, 1e6);
    }

    function testUnderlyingAndVaultDifferentDecimals_case2(uint128 depositAmount) public {
        // underlying has 18 decimals (e.g., WETH), vault shares have 6 decimals
        MockERC20 underlying = new MockERC20("WETH", "WETH", 18);
        MockERC4626WithDecimals vault = new MockERC4626WithDecimals(IERC20Metadata(address(underlying)), 6);

        underlying.mint(address(this), depositAmount);
        underlying.approve(address(vault), depositAmount);

        vault.deposit(depositAmount, address(this));

        MockAggWithAsset agg = new MockAggWithAsset(address(this), address(underlying));
        MockPriceFeedV2.RoundData memory rd = MockPriceFeedV2.RoundData({
            roundId: 2,
            answer: int256(1500 * 10 ** 8), // $1500
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        agg.updateRoundData(rd);

        TermMaxERC4626PriceFeed priceFeed = new TermMaxERC4626PriceFeed(address(agg), address(vault));
        (, int256 feedAnswer,,,) = priceFeed.latestRoundData();

        uint256 vaultDenominator = 10 ** uint256(vault.decimals());
        uint256 vaultAnswer = vault.convertToAssets(vaultDenominator);
        uint8 aggDecimals = agg.decimals();
        uint8 underlyingDecimals = underlying.decimals();
        uint256 priceDenominator = 10 ** uint256(aggDecimals + underlyingDecimals);
        uint256 PRICE_DECIMALS = 10 ** 8;
        uint256 aggAnswer2 = uint256(1500 * 10 ** 8);
        uint256 expected2 = (aggAnswer2 * vaultAnswer * PRICE_DECIMALS) / priceDenominator;
        assertEq(feedAnswer, int256(expected2));
        // check answer is around 1500 USD
        assertApproxEqAbs(uint256(feedAnswer), expected2, 1e6);
    }
}
