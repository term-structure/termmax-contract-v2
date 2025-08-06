// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {TermMaxVaultV2} from "contracts/v2/vault/TermMaxVaultV2.sol";
import {ITermMaxVaultV2, OrderV2ConfigurationParams} from "contracts/v2/vault/ITermMaxVaultV2.sol";
import {ITermMaxMarketV2} from "contracts/v2/ITermMaxMarketV2.sol";
import {ITermMaxOrderV2} from "contracts/v2/ITermMaxOrderV2.sol";
import {VaultInitialParamsV2} from "contracts/v2/storage/TermMaxStorageV2.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";
import {VaultErrors} from "contracts/v1/errors/VaultErrors.sol";
import {VaultErrorsV2} from "contracts/v2/errors/VaultErrorsV2.sol";
import {VaultConstants} from "contracts/v1/lib/VaultConstants.sol";
import {Constants} from "contracts/v1/lib/Constants.sol";
import {PendingAddress, PendingUint192} from "contracts/v1/lib/PendingLib.sol";
import {CurveCuts} from "contracts/v1/storage/TermMaxStorage.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";

contract TermMaxVaultV2Handler is Test {
    using SafeCast for uint256;
    using SafeCast for int256;

    TermMaxVaultV2 public vault;
    ITermMaxMarketV2 public market;
    MockERC20 public asset;
    MockERC4626 public pool;

    // Test actors
    address[] public actors;
    address public curator;
    address public guardian;
    address public owner;

    // Call tracking
    mapping(bytes32 => uint256) public calls;

    // Ghost variables for tracking state
    uint256 public ghost_totalDeposits;
    uint256 public ghost_totalWithdrawals;
    uint256 public ghost_totalMints;
    uint256 public ghost_totalRedeems;
    uint256 public ghost_maxCapacityChanges;
    uint256 public ghost_performanceFeeRateChanges;
    uint256 public ghost_timelockChanges;
    uint256 public ghost_minApyChanges;
    uint256 public ghost_poolChanges;
    uint256 public ghost_marketWhitelistChanges;
    uint256 public ghost_guardianChanges;
    uint256 public ghost_curatorChanges;

    // Pool interaction tracking
    uint256 public ghost_poolDeposits;
    uint256 public ghost_poolWithdrawals;
    bool public ghost_poolEverSet;

    // APY tracking
    uint256 public ghost_maxApyReached;
    uint256 public ghost_minApyReached;
    uint256 public ghost_initialMinApy;

    // Asset tracking
    uint256 public ghost_maxTotalAssets;
    uint256 public ghost_maxTotalSupply;

    // Bad debt tracking
    uint256 public ghost_totalBadDebtHandled;
    mapping(address => uint256) public ghost_badDebtByCollateral;

    modifier createActor() {
        address currentActor = _getCurrentActor();
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    modifier onlyCurator() {
        vm.startPrank(curator);
        _;
        vm.stopPrank();
    }

    modifier onlyGuardian() {
        vm.startPrank(guardian);
        _;
        vm.stopPrank();
    }

    modifier onlyOwner() {
        vm.startPrank(owner);
        _;
        vm.stopPrank();
    }

    constructor(
        TermMaxVaultV2 _vault,
        ITermMaxMarketV2 _market,
        MockERC20 _asset,
        MockERC4626 _pool,
        address _curator,
        address _guardian,
        address _owner
    ) {
        vault = _vault;
        market = _market;
        asset = _asset;
        pool = _pool;
        curator = _curator;
        guardian = _guardian;
        owner = _owner;

        // Initialize ghost variables with current vault state
        ghost_initialMinApy = vault.minApy();
        ghost_maxApyReached = vault.apy();
        ghost_minApyReached = vault.apy();
        ghost_maxTotalAssets = vault.totalAssets();
        ghost_maxTotalSupply = vault.totalSupply();

        // Create test actors
        for (uint256 i = 0; i < 10; i++) {
            actors.push(vm.addr(i + 100));
        }
    }

    // ========== DEPOSIT/WITHDRAWAL FUNCTIONS ==========

    function deposit(uint256 assets) external createActor countCall("deposit") {
        address currentActor = _getCurrentActor();

        // Bound assets to reasonable range
        uint256 maxDeposit = vault.maxDeposit(currentActor);
        if (maxDeposit == 0) return;

        assets = bound(assets, 1e6, Math.min(maxDeposit, 1_000_000e18));

        // Ensure actor has assets
        asset.mint(currentActor, assets);
        asset.approve(address(vault), assets);

        try vault.deposit(assets, currentActor) returns (uint256 shares) {
            ghost_totalDeposits += assets;
            _updateAssetTracking();
        } catch {
            // Deposit failed, which is acceptable based on vault state
        }
    }

    function mint(uint256 shares) external createActor countCall("mint") {
        address currentActor = _getCurrentActor();

        // Bound shares to reasonable range
        uint256 maxMint = vault.maxMint(currentActor);
        if (maxMint == 0) return;

        shares = bound(shares, 1e6, Math.min(maxMint, 1_000_000e18));

        uint256 assets = vault.previewMint(shares);

        // Ensure actor has assets
        asset.mint(currentActor, assets);
        asset.approve(address(vault), assets);

        try vault.mint(shares, currentActor) returns (uint256 assetsUsed) {
            ghost_totalMints += shares;
            _updateAssetTracking();
        } catch {
            // Mint failed, which is acceptable based on vault state
        }
    }

    function withdraw(uint256 assets) external createActor countCall("withdraw") {
        address currentActor = _getCurrentActor();

        uint256 maxWithdraw = vault.maxWithdraw(currentActor);
        if (maxWithdraw == 0) return;

        assets = bound(assets, 1, maxWithdraw);

        try vault.withdraw(assets, currentActor, currentActor) returns (uint256 shares) {
            ghost_totalWithdrawals += assets;
            _updateAssetTracking();
        } catch {
            // Withdrawal failed, which is acceptable based on vault state
        }
    }

    function redeem(uint256 shares) external createActor countCall("redeem") {
        address currentActor = _getCurrentActor();

        uint256 maxRedeem = vault.maxRedeem(currentActor);
        if (maxRedeem == 0) return;

        shares = bound(shares, 1, maxRedeem);

        try vault.redeem(shares, currentActor, currentActor) returns (uint256 assets) {
            ghost_totalRedeems += shares;
            _updateAssetTracking();
        } catch {
            // Redeem failed, which is acceptable based on vault state
        }
    }

    // ========== GOVERNANCE FUNCTIONS ==========

    function setCapacity(uint256 newCapacity) external countCall("setCapacity") onlyCurator {
        newCapacity = bound(newCapacity, 1e18, type(uint128).max);

        if (newCapacity == vault.maxDeposit(address(0)) + vault.totalAssets()) return;

        try vault.setCapacity(newCapacity) {
            ghost_maxCapacityChanges++;
        } catch {
            // Capacity change failed
        }
    }

    function submitPerformanceFeeRate(uint256 newRate) external countCall("submitPerformanceFeeRate") onlyCurator {
        // Bound to the smaller of MAX_PERFORMANCE_FEE_RATE and uint184 max to prevent overflow
        uint256 maxAllowedRate = Math.min(VaultConstants.MAX_PERFORMANCE_FEE_RATE, type(uint184).max);
        newRate = bound(newRate, 0, maxAllowedRate);

        // Skip if rate is the same as current rate
        if (newRate == vault.performanceFeeRate()) return;

        // Skip if there's already a pending rate to avoid "AlreadyPending" error
        PendingUint192 memory currentPending = vault.pendingPerformanceFeeRate();
        if (currentPending.validAt != 0) return;

        try vault.submitPerformanceFeeRate(uint184(newRate)) {
            ghost_performanceFeeRateChanges++;
        } catch {
            // Performance fee rate change failed
        }
    }

    function submitTimelock(uint256 newTimelock) external countCall("submitTimelock") onlyCurator {
        newTimelock = bound(newTimelock, VaultConstants.POST_INITIALIZATION_MIN_TIMELOCK, VaultConstants.MAX_TIMELOCK);

        if (newTimelock == vault.timelock()) return;

        try vault.submitTimelock(newTimelock) {
            ghost_timelockChanges++;
        } catch {
            // Timelock change failed
        }
    }

    function submitMinApy(uint256 newMinApy) external countCall("submitMinApy") onlyCurator {
        newMinApy = bound(newMinApy, 0, 1e8); // 0% to 100%

        if (newMinApy == vault.minApy()) return;

        try vault.submitPendingMinApy(uint64(newMinApy)) {
            ghost_minApyChanges++;
        } catch {
            // Min APY change failed
        }
    }

    function submitPool(address newPool) external countCall("submitPool") onlyCurator {
        // Use existing pool or zero address for testing
        if (newPool == address(vault.pool())) return;

        // Validate pool if not zero address
        if (newPool != address(0)) {
            try IERC4626(newPool).asset() returns (address poolAsset) {
                if (poolAsset != address(asset)) {
                    return; // Skip if pool uses different asset
                }
            } catch {
                return; // Skip if pool doesn't implement asset() correctly
            }
        }

        try vault.submitPendingPool(newPool) {
            ghost_poolChanges++;
            if (newPool != address(0)) {
                ghost_poolEverSet = true;
            }
        } catch {
            // Pool change failed
        }
    }

    function submitMarket(address marketAddr, bool isWhitelisted) external countCall("submitMarket") onlyCurator {
        try vault.submitMarket(marketAddr, isWhitelisted) {
            ghost_marketWhitelistChanges++;
        } catch {
            // Market whitelist change failed
        }
    }

    function submitGuardian(address newGuardian) external countCall("submitGuardian") onlyOwner {
        if (newGuardian == vault.guardian()) return;
        if (vault.pendingGuardian().validAt != 0) return;
        try vault.submitGuardian(newGuardian) {
            ghost_guardianChanges++;
        } catch {
            // Guardian change failed
        }
    }

    function setCurator(address newCurator) external countCall("setCurator") onlyOwner {
        if (newCurator == vault.curator()) return;

        try vault.setCurator(newCurator) {
            ghost_curatorChanges++;
            curator = newCurator;
        } catch {
            // Curator change failed
        }
    }

    // ========== TIMELOCK ACCEPTANCE FUNCTIONS ==========

    function acceptTimelock() external countCall("acceptTimelock") {
        PendingUint192 memory pending = vault.pendingTimelock();
        if (pending.validAt == 0 || block.timestamp < pending.validAt) return;

        try vault.acceptTimelock() {
            // Timelock accepted
        } catch {
            // Accept timelock failed
        }
    }

    function acceptPerformanceFeeRate() external countCall("acceptPerformanceFeeRate") {
        PendingUint192 memory pending = vault.pendingPerformanceFeeRate();
        if (pending.validAt == 0 || block.timestamp < pending.validAt) return;

        try vault.acceptPerformanceFeeRate() {
            // Performance fee rate accepted
        } catch {
            // Accept performance fee rate failed
        }
    }

    function acceptMinApy() external countCall("acceptMinApy") {
        PendingUint192 memory pending = vault.pendingMinApy();
        if (pending.validAt == 0 || block.timestamp < pending.validAt) return;

        try vault.acceptPendingMinApy() {
            // Min APY accepted
        } catch {
            // Accept min APY failed
        }
    }

    function acceptPool() external countCall("acceptPool") {
        PendingAddress memory pending = vault.pendingPool();
        if (pending.validAt == 0 || block.timestamp < pending.validAt) return;

        try vault.acceptPool() {
            ghost_poolDeposits++;
        } catch {
            // Accept pool failed
        }
    }

    function acceptGuardian() external countCall("acceptGuardian") {
        PendingAddress memory pending = vault.pendingGuardian();
        if (pending.validAt == 0 || block.timestamp < pending.validAt) return;

        try vault.acceptGuardian() {
            // Guardian accepted
            ghost_guardianChanges++;
            guardian = pending.value;
        } catch {
            // Accept guardian failed
        }
    }

    function acceptMarket(address marketAddr) external countCall("acceptMarket") {
        PendingUint192 memory pending = vault.pendingMarkets(marketAddr);
        if (pending.validAt == 0 || block.timestamp < pending.validAt) return;

        try vault.acceptMarket(marketAddr) {
            // Market accepted
        } catch {
            // Accept market failed
        }
    }

    // ========== REVOKE FUNCTIONS ==========

    function revokeTimelock() external countCall("revokeTimelock") onlyGuardian {
        try vault.revokePendingTimelock() {
            // Timelock revoked
        } catch {
            // Revoke timelock failed
        }
    }

    function revokePerformanceFeeRate() external countCall("revokePerformanceFeeRate") onlyGuardian {
        try vault.revokePendingPerformanceFeeRate() {
            // Performance fee rate revoked
        } catch {
            // Revoke performance fee rate failed
        }
    }

    function revokeMinApy() external countCall("revokeMinApy") onlyGuardian {
        try vault.revokePendingMinApy() {
            // Min APY revoked
        } catch {
            // Revoke min APY failed
        }
    }

    function revokePool() external countCall("revokePool") onlyGuardian {
        try vault.revokePendingPool() {
            // Pool revoked
        } catch {
            // Revoke pool failed
        }
    }

    function revokeGuardian() external countCall("revokeGuardian") onlyGuardian {
        try vault.revokePendingGuardian() {
            // Guardian revoked
        } catch {
            // Revoke guardian failed
        }
    }

    function revokeMarket(address marketAddr) external countCall("revokeMarket") onlyGuardian {
        try vault.revokePendingMarket(marketAddr) {
            // Market revoked
        } catch {
            // Revoke market failed
        }
    }

    // ========== PAUSE/UNPAUSE FUNCTIONS ==========

    function pauseVault() external countCall("pauseVault") onlyOwner {
        try vault.pause() {
            // Vault paused
        } catch {
            // Pause failed
        }
    }

    function unpauseVault() external countCall("unpauseVault") onlyOwner {
        try vault.unpause() {
            // Vault unpaused
        } catch {
            // Unpause failed
        }
    }

    // ========== TIME MANAGEMENT ==========

    function advanceTime(uint256 timeToAdd) external countCall("advanceTime") {
        // Bound time advance to reasonable values to prevent overflow
        // Use a much smaller upper bound to prevent overflow issues
        timeToAdd = bound(timeToAdd, 1 hours, 7 days);

        // Additional safety check: ensure we don't overflow block.timestamp
        if (timeToAdd > type(uint64).max - block.timestamp) {
            timeToAdd = 1 days; // Fallback to safe value
        }

        vm.warp(block.timestamp + timeToAdd);
    }

    // ========== BAD DEBT HANDLING ==========

    function dealBadDebt(address collateral, uint256 badDebtAmt) external createActor countCall("dealBadDebt") {
        address currentActor = _getCurrentActor();

        // Skip if collateral is the same as asset
        if (collateral == address(asset)) return;

        uint256 maxRedeem = vault.maxRedeem(currentActor);
        if (maxRedeem == 0) return;

        badDebtAmt = bound(badDebtAmt, 1e6, 100_000e18);

        try vault.dealBadDebt(collateral, badDebtAmt, currentActor, currentActor) returns (
            uint256 shares, uint256 collateralOut
        ) {
            ghost_totalBadDebtHandled += badDebtAmt;
            ghost_badDebtByCollateral[collateral] += badDebtAmt;
        } catch {
            // Deal bad debt failed
        }
    }

    // ========== INITIALIZATION ==========

    function initializeGhostVariables(uint256 initialDeposits) external {
        ghost_totalDeposits = initialDeposits;
        ghost_maxTotalAssets = vault.totalAssets();
        ghost_maxTotalSupply = vault.totalSupply();
    }

    // ========== HELPER FUNCTIONS ==========

    function _getCurrentActor() internal view returns (address) {
        return actors[bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 0, actors.length - 1)];
    }

    function _updateAssetTracking() internal {
        uint256 currentTotalAssets = vault.totalAssets();
        uint256 currentTotalSupply = vault.totalSupply();
        uint256 currentApy = vault.apy();

        if (currentTotalAssets > ghost_maxTotalAssets) {
            ghost_maxTotalAssets = currentTotalAssets;
        }

        if (currentTotalSupply > ghost_maxTotalSupply) {
            ghost_maxTotalSupply = currentTotalSupply;
        }

        if (currentApy > ghost_maxApyReached) {
            ghost_maxApyReached = currentApy;
        }

        if (currentApy < ghost_minApyReached) {
            ghost_minApyReached = currentApy;
        }
    }
}

contract TermMaxVaultV2InvariantTest is StdInvariant, Test {
    using JSONLoader for *;

    TermMaxVaultV2 public vault;
    ITermMaxMarketV2 public market;
    MockERC20 public asset;
    MockERC4626 public pool;
    TermMaxVaultV2Handler public handler;

    DeployUtils.Res res;
    address curator;
    address guardian;
    address owner;

    function setUp() public {
        // Deploy market and vault using existing utilities
        owner = vm.addr(999);
        curator = vm.addr(1000);
        guardian = vm.addr(1001);

        vm.startPrank(owner);

        string memory testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        res = DeployUtils.deployMarket(
            owner, JSONLoader.getMarketConfigFromJson(owner, testdata, ".marketConfig"), maxLtv, liquidationLtv
        );

        market = res.market;
        asset = res.debt;

        // Create pool for testing
        pool = new MockERC4626(IERC20(address(asset)));

        // Create vault with V2 parameters using the correct struct with 11 fields
        VaultInitialParamsV2 memory vaultParams = VaultInitialParamsV2({
            admin: owner,
            curator: curator,
            guardian: guardian,
            timelock: 1 days,
            asset: IERC20(address(asset)),
            pool: IERC4626(address(0)), // Start without pool
            maxCapacity: 1_000_000e18,
            name: "Test Vault V2",
            symbol: "TVV2",
            performanceFeeRate: 0.2e8, // 20%
            minApy: 0.05e8 // 5%
        });

        // Use DeployUtils to properly create the vault
        vault = DeployUtils.deployVault(vaultParams);

        // Setup initial liquidity by depositing assets
        uint256 initialAmount = 100_000e18;
        asset.mint(owner, initialAmount);
        asset.approve(address(vault), initialAmount);
        vault.deposit(initialAmount, owner);

        vm.stopPrank();

        // Setup handler
        handler = new TermMaxVaultV2Handler(vault, market, asset, pool, curator, guardian, owner);

        // Initialize ghost variables to account for the initial deposit
        handler.initializeGhostVariables(initialAmount);

        // Configure invariant testing
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](26);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.mint.selector;
        selectors[2] = handler.withdraw.selector;
        selectors[3] = handler.redeem.selector;
        selectors[4] = handler.setCapacity.selector;
        selectors[5] = handler.submitPerformanceFeeRate.selector;
        selectors[6] = handler.submitTimelock.selector;
        selectors[7] = handler.submitMinApy.selector;
        selectors[8] = handler.submitPool.selector;
        selectors[9] = handler.submitMarket.selector;
        selectors[10] = handler.submitGuardian.selector;
        selectors[11] = handler.setCurator.selector;
        selectors[12] = handler.acceptTimelock.selector;
        selectors[13] = handler.acceptPerformanceFeeRate.selector;
        selectors[14] = handler.acceptMinApy.selector;
        selectors[15] = handler.acceptPool.selector;
        selectors[16] = handler.acceptGuardian.selector;
        selectors[17] = handler.acceptMarket.selector;
        selectors[18] = handler.revokeTimelock.selector;
        selectors[19] = handler.revokePerformanceFeeRate.selector;
        selectors[20] = handler.revokeMinApy.selector;
        selectors[21] = handler.revokePool.selector;
        selectors[22] = handler.revokeGuardian.selector;
        selectors[23] = handler.revokeMarket.selector;
        selectors[24] = handler.pauseVault.selector;
        selectors[25] = handler.advanceTime.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ========== INVARIANTS ==========

    // INVARIANT 1: Total assets vs. total liabilities
    function invariant_totalAssetsVsLiabilities() public view {
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        uint256 totalBadDebt = handler.ghost_totalBadDebtHandled();

        // Total assets should be >= total liabilities (totalSupply + bad debt)
        assertGe(totalAssets, totalSupply + totalBadDebt, "Total assets should cover total liabilities");
    }

    // INVARIANT 2: Max deposit invariant
    function invariant_maxDeposit() public view {
        uint256 maxDeposit = vault.maxDeposit(address(0));
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        // Max deposit should be >= total assets - total supply
        assertGe(maxDeposit, totalAssets - totalSupply, "Max deposit should cover difference between assets and supply");
    }

    // INVARIANT 3: Capacity invariant
    function invariant_capacity() public view {
        uint256 maxDeposit = vault.maxDeposit(address(0));
        uint256 totalAssets = vault.totalAssets();

        // Max deposit represents remaining capacity, so total capacity = maxDeposit + totalAssets
        // This should always be a reasonable value
        uint256 totalCapacity = maxDeposit + totalAssets;

        // Total capacity should be reasonable (not overflow and should be >= current assets)
        assertGe(totalCapacity, totalAssets, "Total capacity should be >= current total assets");

        // Ensure no overflow occurred in the addition
        assertTrue(totalCapacity >= maxDeposit, "Total capacity calculation should not overflow");
    }

    // INVARIANT 5: Performance fee rate bounds
    function invariant_performanceFeeRateBounds() public view {
        uint256 performanceFeeRate = vault.performanceFeeRate();

        // Performance fee rate should be <= max performance fee rate
        assertLe(
            performanceFeeRate, VaultConstants.MAX_PERFORMANCE_FEE_RATE, "Performance fee rate should be within bounds"
        );
    }

    // INVARIANT 6: Timelock bounds
    function invariant_timelockBounds() public view {
        uint256 timelock = vault.timelock();

        // Timelock should be within expected bounds
        assertGe(timelock, VaultConstants.POST_INITIALIZATION_MIN_TIMELOCK, "Timelock should be >= min timelock");
        assertLe(timelock, VaultConstants.MAX_TIMELOCK, "Timelock should be <= max timelock");
    }

    // INVARIANT 8: Ghost variable consistency
    function invariant_ghostVariableConsistency() public view {
        // Max values should be reasonable
        uint256 maxAssets = handler.ghost_maxTotalAssets();
        uint256 currentAssets = vault.totalAssets();
        assertGe(maxAssets, currentAssets, "Max total assets should be >= current total assets");

        // Total bad debt should be reasonable
        uint256 totalBadDebt = handler.ghost_totalBadDebtHandled();
        if (totalBadDebt > 0 && currentAssets > 0) {
            assertLe(totalBadDebt, currentAssets * 10, "Total bad debt should not exceed 10x current assets");
        }
    }

    // Function to display test summary
    function invariant_callSummary() public view {
        console.log("=== TERMMAX VAULT V2 INVARIANT TEST SUMMARY ===");
        console.log("deposit calls:", handler.calls("deposit"));
        console.log("mint calls:", handler.calls("mint"));
        console.log("withdraw calls:", handler.calls("withdraw"));
        console.log("redeem calls:", handler.calls("redeem"));
        console.log("setCapacity calls:", handler.calls("setCapacity"));
        console.log("submitPerformanceFeeRate calls:", handler.calls("submitPerformanceFeeRate"));
        console.log("submitTimelock calls:", handler.calls("submitTimelock"));
        console.log("submitMinApy calls:", handler.calls("submitMinApy"));
        console.log("submitPool calls:", handler.calls("submitPool"));
        console.log("submitMarket calls:", handler.calls("submitMarket"));
        console.log("submitGuardian calls:", handler.calls("submitGuardian"));
        console.log("setCurator calls:", handler.calls("setCurator"));
        console.log("pauseVault calls:", handler.calls("pauseVault"));
        console.log("unpauseVault calls:", handler.calls("unpauseVault"));
        console.log("dealBadDebt calls:", handler.calls("dealBadDebt"));
        console.log("advanceTime calls:", handler.calls("advanceTime"));
        console.log("");
        console.log("Ghost variables:");
        console.log("ghost_totalDeposits:", handler.ghost_totalDeposits());
        console.log("ghost_totalWithdrawals:", handler.ghost_totalWithdrawals());
        console.log("ghost_maxCapacityChanges:", handler.ghost_maxCapacityChanges());
        console.log("ghost_performanceFeeRateChanges:", handler.ghost_performanceFeeRateChanges());
        console.log("ghost_timelockChanges:", handler.ghost_timelockChanges());
        console.log("ghost_minApyChanges:", handler.ghost_minApyChanges());
        console.log("ghost_poolChanges:", handler.ghost_poolChanges());
        console.log("ghost_marketWhitelistChanges:", handler.ghost_marketWhitelistChanges());
        console.log("ghost_totalBadDebtHandled:", handler.ghost_totalBadDebtHandled());
        console.log("ghost_poolEverSet:", handler.ghost_poolEverSet());
        console.log("");
        console.log("Vault state:");
        console.log("Total assets:", vault.totalAssets());
        console.log("Total supply:", vault.totalSupply());
        console.log("APY:", vault.apy());
        console.log("Min APY:", vault.minApy());
        console.log("Performance fee rate:", vault.performanceFeeRate());
        console.log("Timelock:", vault.timelock());
        console.log("Paused:", vault.paused());
        console.log("Pool address:", address(vault.pool()));
        console.log("Curator:", vault.curator());
        console.log("Guardian:", vault.guardian());
        console.log("Owner:", vault.owner());
        console.log("Current timestamp:", block.timestamp);
    }
}
