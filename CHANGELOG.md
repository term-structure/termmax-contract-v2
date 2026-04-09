# Changelog - TermMax Contract

All notable changes to this project are documented in this file.

## 2026-03-20 - PR #21 (from dev)

### Deployments
- Updated contract deployment information.

## 2026-03-20 - PR #20 (from dev)

### Refactor
- Removed unused swap adapter contracts and cleaned up related code.

## 2026-03-20 - PR #19 (fix/uniswap_adapter_v2)

### Fixed
- Fixed an issue in the Uniswap V2 adapter.

### Added
- Added a maximum update interval to the Ondo price feed adapter.
- Refactored `ERC20SwapAdapterV2` to inherit from `ERC20SwapAdapterV1` and improved swap behavior for compatibility with the v1 router.

## 2026-03-20 - PR #18 (feature/lifi_swap_adapter)

### Added
- Added the `LifiSwapAdapter` as a LiFi aggregation swap adapter with selector validation and error handling.

### Fixed
- Fixed an allowance-related DoS issue.
- Fixed the adapter refund mechanism to prevent tokens from being locked in the GT contract.

## 2026-03-20 - PR #17 (fix/ondo_pricefeed_timestamp)

### Added
- Added a maximum update interval to the Ondo price feed adapter.

## 2026-03-02 - PR #15 (from dev)

### Added
- Added `TermMaxBeefySharePriceFeedAdapter` to retrieve Beefy Vault share prices.
- Used fair price calculations for LP token valuation.

### Fixed
- Fixed related issues and documentation wording.

## 2026-02-25 - PR #14 (from dev)

### Added
- Added the `ISupraSValueFeed` interface and `TermMaxB2TokenPriceFeedAdapter` for B2 chain price data.
- Added `TermMaxUSPCPriceFeedAdapter` and its integration tests.
- Added an Ondo protocol price feed adapter under `feat/ondo_pricefeed_adapter`.
- Added `StableERC4626ForVenus` for Venus deposits, withdrawals, and yield accounting.
- Added `StableERC4626ForCustomize` and factory support for custom ERC4626 pools.
- Updated `OKX ScaleHelper` and related tests.

### Fixed
- Removed redundant storage from the price feed converter.
- Set the refund address to `msg.sender` when `address(0)` is provided.
- Accrued interest before deposits and withdrawals.
- Enhanced `OndoSwapAdapter` to track `USDon` balances and improve swap logic.

## 2026-02-10 - PR #11, #12, #13 (from dev / fix/ondo_adapter)

### Added
- Added `StableERC4626ForVenus` under `feat/venus` with buffer management and income asset handling.
- Added `FactoryErrorsV2` and `StableERC4626ForCustomize` support in `TermMax4626Factory` under `feat/customize_pool`.
- Upgraded the OKX swap adapter under `update/okx_adapter_20260121`.

### Fixed
- Fixed the `address(0)` refund logic in the Ondo adapter in PR #12 (`fix/ondo_adapter_20260210`).

## 2026-02-02 - PR #10 (from dev)

### Added
- Added `StableERC4626ForVenus` and `StableERC4626ForCustomize` with buffer management and income asset handling.
- Enhanced `OkxSwapHelper`.
- Enhanced `OndoSwapAdapter` with `USDon` refunds and improved swap behavior.
- Added `FactoryErrorsV2` and dynamic implementation management to `TermMax4626Factory`.
- Added asset withdrawal and initialization events in `ERC4626TokenEvents`.

### Fixed
- Cleared `tstore` state after use.

## 2026-01-22 - PR #9 (temp/merge_dev_before_fix)

### Added
- Added `OneInchSwapAdapter` and related tests.
- Added `OndoSwapAdapter` to compute net `USDC` and `USDT` outputs.
- Added refund address support to `TermMaxSwapAdapter`.
- Added a price feed adapter for the `DUSD` token.
- Added an OFT version of the TMX token contract.

### Fixed
- Fixed issues in the rollover flow under `fix/rollover_issue_20260120`.
- Fixed refund logic for exact-output swaps in `TermMaxSwapAdapter`.
- Fixed the contract title in `OneInchSwapAdapter`.

## 2025-12-04 - PR #7 (from feat/order_earn_interest)

### Added
- Added `PancakeSmartAdapter`, Pancake helper utilities, and full test coverage.
- Added rollover support to the router contract.

### Fixed
- Fixed event definition issues.
- Fixed related issues and removed the Stroom adapter.

## 2025-12-02 - PR #5 (from feat/order_earn_interest)

### Added
- Added `ITermMax4626Pool`, `ITermMaxVault`, and the `TermMaxViewer` contract with tests.
- Added exact-position leverage and updated flash loan handling.
- Added `TermMaxWeETHPriceCapAdapter` based on AAVE's `WeETHPriceCapAdapter`, along with deployment scripts and fork tests.
- Added `IKodiakRouter` and `KodiakSwapAdapter`.
- Added an OKX swap adapter.
- Added `SimpleAggregator` for price retrieval and oracle management.
- Added an `srUSDe` oracle adapter.
- Deployed the TMX token contract.
- Updated `RouterV1.1.2` with:
	- upgradeable reentrancy protection via `ReentrancyGuardUpgradeable` and `nonReentrant` on critical external entry points;
	- support for the `EXACT_POSITION` flash loan type for exact-position leverage;
	- stronger callback validation through `onlyCallbackAddress` and `T_CALLBACK_ADDRESS_STORE`;
	- new or extended routing methods including `swapExactTokenToTokenWithDex`, `sellCall`, `flashRepayFromColl` with `expectedOutput`, and `flashRepayToGetCollateral`;
	- stricter adapter whitelist checks and selected `delegatecall` flows for `approveOutputToken`;
	- a refactored `executeOperation` flow split between `_exactPositionLeverage` and `_generalLeverage`;
	- reentrancy guard initialization through `__ReentrancyGuard_init_unchained()` in `initialize`.

### Fixed
- Added collateral checks to `GearingTokenWithERC20V2`.
- Allowed full liquidation when collateral cannot fully cover debt.
- Refactored `maxRedeem` to use the minimum of `userAssets` and `totalBadDebt`.
- Set `debtInAmt` to `0` in the `IssueGt` event for clarity.
- Removed unnecessary reverts for empty swap units in `TermMaxRouter`.
- Replaced `safeIncreaseAllowance` with `safeApprove` in swap adapters.

## 2025-10-20 - PR #3 (from feat/order_earn_interest)

### Added
- Added Uniswap V3 and PancakeSwap TWAP oracle contracts and tests.
- Added `OnlyDeliveryGearingToken`, a delivery-only GT that cannot be liquidated, remove collateral, or increase debt.
- Added support for flash repay to obtain collateral tokens.
- Added exact-output support to the Uniswap adapter.

### Deployments
- Deployed markets and vaults to HyperEVM, Ethereum, Arbitrum, and BNB.
- Upgraded routers on Ethereum, Arbitrum, and BNB.
- Added deployment scripts for Pancake and Uniswap price feeds.
- Deployed Stable ERC4626 for 4626.

## 2025-10-13 - PR #2 (from feat/order_earn_interest)

### Added
- Emitted the actual debt token input amount in events.

### Fixed
- Removed partial flash repay and rollover logic from `RouterV2` to fix partial flash repay issues.
- Fixed the issue that allowed GT positions to repay or remove collateral after maturity.
- Fixed a potential `badDebt` overflow.
- Fixed Chainlink dependency issues.

### Deployments
- Deployed V2 core contracts to Ethereum, Arbitrum, and BNB mainnets.
- Deployed the BNB AAVE pool and vault.

## 2025-09-25 - PR #1 (from feat/order_earn_interest)

### Added
- Added `WhitelistManager` to protect users.
- Added versioned functionality to `AccessManagerV2`.
- Deployed `MakerHelper` to Ethereum, Arbitrum, and BNB.
- Allowed `updateOrder` and liquidity withdrawals while the vault is paused.

### Fixed
- Fixed an issue where GT could potentially be stolen.
- Fixed an issue where force approve could be used with ERC721 tokens.
- Added reentrancy protection to `TermMaxRouter`.
- Fixed missing checks when redeeming orders from the vault.
- Fixed zero-debt loans being unable to remove collateral.
- Fixed an issue blocking pool share withdrawals from orders.
- Fixed non-atomic updates between virtual XT reserve and curve update functions.
- Updated `repayAndRemoveCollateral` so it no longer burns GT tokens.
- Fixed CVF audit issues: CVF-2, CVF-3, CVF-13, CVF-16, CVF-60, CVF-65, CVF-69, CVF-84, CVF-85, CVF-88, and CVF-89.
- Added FT balance checks to orders.

## 2025-07-03

### Added
- Added a special swap adapter for the V1 protocol under `v1_special_adapter`.

## 2025-06-04

### Added
- Added the `VersionV2` version management mechanism under `feat/version_managenent`.

## 2025-05-26

### Added
- Added the `PreTMX` token contract under `feat/preTMX`.

## 2025-05-21

### Added
- Added Gearing Token rollup support under `feat/gt_roll_up`.
- Added batch pause and unpause support under `batch_swtich`.
- Updated price feed related contracts under `update_price_feed`.

## 2025-04-08

### Added
- Configured dependency management under `config_dependencies`.

## 2025-03-24

### Added
- Added a Pendle PT redeem adapter under `adapter_pt_redeem`.

## 2025-03-23

### Added
- Added `AccessManagerV2` with whitelist management under `feat/add_access_manager`.

## 2025-03-21

### Added
- Added `TermMaxPriceFeedConverter` under `pPriceFeed_converter`.

## 2025-03-20

### Added
- Added leverage fee support under `feat/leverage_fee`.

## 2025-03-07 to 2025-03-11

### Fixed
- Fixed the curve guessing algorithm under `curve-guess` and `fix/curve-guess`.

## 2025-02-05 to 2025-03-05

### Fixed
- Applied multiple rounds of fixes for issues identified in the Cetina security audit under `v2_fix_cetina_issues`.

## 2025-02-14

### Tests
- Added end-to-end loop tests under `v2_e2e_loop_test`.

## 2025-02-06

### Added
- Added the V2 proof-of-concept base contracts under `v2_poc_base`.
- Added vault deployment scripts under `v2_vault_deploy_script`.

## 2025-02-04

### Refactor
- Split the vault into `OrderManager` and `TermMaxVault` under `v2_split_vault_contract`.

## 2025-02-03

### Fixed
- Fixed review comments under `v2_fix_nic_sugesstions`.

## 2025-01-24

### Added
- Added curve parameter validation under `v2_check_curve`.

## 2025-01-23

### Added
- Added the V2 access control framework under `v2_access_control`.

## 2025-01-22

### Added
- Added routing logic for borrowing workflows under `borrow_story_router`.
- Added vault initialization under `poc/feat/vault_initialize`.

## 2025-01-06

### Fixed
- Fixed reserve accounting during `issueFt` under `fix_issueFt_error_reserve`.

## 2024-12-30

### Fixed
- Fixed issues from the Catina Solo audit under `audit/fix_catina_solo`.

## 2024-12-18

### Added
- Added the Market Curator role and related mechanics under `market_curator`.

### Fixed
- Fixed issues from audit round #10 under `fix_audit_10`.

## 2024-12-16

### Refactor
- Renamed PT price feed related contracts under `Rename-pt-with-price-feed`.
- Removed permit functionality under `Remove-permit-function`.

## 2024-12-15

### Added
- Added withdrawal limits for excess FT and XT under `add-limit-to-withdraw-excess-ft-and-xt`.
- Added oracle add and remove functions under `add_remove_oracle_functions`.

## 2024-12-13

### Fixed
- Fixed issues identified during the audit under `fix_audit`.

## 2024-12-12

### Refactor
- Removed the enlarged LP mechanism under `remove-enlarged-lp`.

## 2024-12-06

### Added
- Added `OracleAggregator` with multi-oracle aggregation support under `oracle_aggregator`.
- Added a liquidity provider whitelist under `add-provider-whitelist`.

## 2024-12-05

### Added
- Added the `MarketViewer` contract for market data queries under `feat/market-viewer`.
- Added flash repay through FT under `flash_repay_through_ft`.

### Fixed
- Fixed issues identified in the Spearbit competition audit under `fix_audit_spearbit_competetion_issues`.

## 2024-11-19 to 2024-11-20

### Added
- Added leveraged position opening with flash loan strategies under `feat/lever-evan`.

## 2024-11-02 to 2024-11-05

### Added
- Merged the V2 MVP contracts into `main` under `2410-ya-mvp`, including the core Market, Order, and Router logic.
- Added the `TermMaxRouter` contract under `feat/router`.

## 2024-10-01

### Initial
- Initialized the V2 development branch by merging `dev` into `main`.
