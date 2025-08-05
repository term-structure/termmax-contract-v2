// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StableERC4626For4626} from "contracts/v2/tokens/StableERC4626For4626.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";
import {MockStableERC4626} from "contracts/v2/test/MockStableERC4626.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/console.sol";

contract StableERC4626For4626Handler is Test {
    StableERC4626For4626 public stable4626;
    MockStableERC4626 public thirdPool;
    MockERC20 public underlying;
    address public admin;

    // Actors for testing
    address[] public actors;
    mapping(bytes32 => uint256) public calls;

    // State tracking
    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_mintedSum;
    uint256 public ghost_burnedSum;
    uint256 public ghost_totalIncomeWithdrawn;

    modifier createActor() {
        address currentActor = msg.sender;
        if (currentActor == address(0) || currentActor == address(this)) {
            currentActor = actors[bound(uint256(keccak256(abi.encode(block.timestamp))), 0, actors.length - 1)];
        }
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    constructor(StableERC4626For4626 _stable4626, MockStableERC4626 _thirdPool, MockERC20 _underlying, address _admin) {
        stable4626 = _stable4626;
        thirdPool = _thirdPool;
        underlying = _underlying;
        admin = _admin;

        // Initialize actors
        for (uint256 i = 0; i < 10; i++) {
            actors.push(vm.addr(i + 1));
        }
    }

    function deposit(uint256 assets) external createActor countCall("deposit") {
        assets = bound(assets, 1, 1000000e6);
        address caller = msg.sender;

        // Mint underlying tokens to the caller
        underlying.mint(caller, assets);
        underlying.approve(address(stable4626), assets);

        uint256 balanceBefore = stable4626.balanceOf(caller);
        uint256 underlyingBalanceBefore = underlying.balanceOf(caller);

        stable4626.deposit(assets, caller);

        // Update ghost variables
        ghost_depositSum += assets;
        ghost_mintedSum += assets; // 1:1 conversion

        // Verify deposit worked correctly
        assertEq(stable4626.balanceOf(caller), balanceBefore + assets);
        assertEq(underlying.balanceOf(caller), underlyingBalanceBefore - assets);
    }

    function withdraw(uint256 assets) external createActor countCall("withdraw") {
        assets = bound(assets, 1, stable4626.maxWithdraw(msg.sender));
        if (assets == 0) return;

        address caller = msg.sender;
        uint256 balanceBefore = stable4626.balanceOf(caller);
        uint256 underlyingBalanceBefore = underlying.balanceOf(caller);

        stable4626.withdraw(assets, caller, caller);

        // Update ghost variables
        ghost_withdrawSum += assets;
        ghost_burnedSum += assets; // 1:1 conversion

        // Verify withdraw worked correctly
        assertEq(stable4626.balanceOf(caller), balanceBefore - assets);
        assertEq(underlying.balanceOf(caller), underlyingBalanceBefore + assets);
    }

    function redeem(uint256 shares) external createActor countCall("redeem") {
        shares = bound(shares, 1, stable4626.balanceOf(msg.sender));
        if (shares == 0) return;

        address caller = msg.sender;
        uint256 balanceBefore = stable4626.balanceOf(caller);
        uint256 underlyingBalanceBefore = underlying.balanceOf(caller);

        stable4626.redeem(shares, caller, caller);

        // Update ghost variables
        ghost_withdrawSum += shares; // 1:1 conversion
        ghost_burnedSum += shares;

        // Verify redeem worked correctly
        assertEq(stable4626.balanceOf(caller), balanceBefore - shares);
        assertEq(underlying.balanceOf(caller), underlyingBalanceBefore + shares);
    }

    function mint(uint256 shares) external createActor countCall("mint") {
        shares = bound(shares, 1, 1000000e6);
        address caller = msg.sender;

        // For stable 4626, mint amount equals shares (1:1)
        uint256 assets = shares;

        // Mint underlying tokens to the caller
        underlying.mint(caller, assets);
        underlying.approve(address(stable4626), assets);

        uint256 balanceBefore = stable4626.balanceOf(caller);
        uint256 underlyingBalanceBefore = underlying.balanceOf(caller);

        stable4626.mint(shares, caller);

        // Update ghost variables
        ghost_depositSum += assets;
        ghost_mintedSum += shares;

        // Verify mint worked correctly
        assertEq(stable4626.balanceOf(caller), balanceBefore + shares);
        assertEq(underlying.balanceOf(caller), underlyingBalanceBefore - assets);
    }

    function simulateYield() external countCall("simulateYield") {
        uint256 yieldAmount = bound(uint256(keccak256(abi.encode(block.timestamp))), 1e6, 100e6);

        // Simulate yield by minting tokens to the third pool
        underlying.mint(address(thirdPool), yieldAmount);
    }

    function withdrawIncomeAssets(uint256 amount) external countCall("withdrawIncomeAssets") {
        uint256 totalIncomeAssets = stable4626.totalIncomeAssets();
        if (totalIncomeAssets == 0) return;

        amount = bound(amount, 1, totalIncomeAssets);

        vm.startPrank(admin);
        uint256 adminBalanceBefore = underlying.balanceOf(admin);

        stable4626.withdrawIncomeAssets(address(underlying), admin, amount);

        ghost_totalIncomeWithdrawn += amount;

        // Verify income withdrawal
        assertEq(underlying.balanceOf(admin), adminBalanceBefore + amount);
        vm.stopPrank();
    }

    function updateBufferConfig(uint256 minBuffer, uint256 maxBuffer, uint256 buffer) external countCall("updateBufferConfig") {
        vm.startPrank(admin);

        minBuffer = bound(minBuffer, 100e6, 5000e6);
        maxBuffer = bound(maxBuffer, minBuffer, 50000e6);
        buffer = bound(buffer, minBuffer, maxBuffer);

        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: minBuffer, maximumBuffer: maxBuffer, buffer: buffer});

        stable4626.updateBufferConfigAndAddReserves(0, newConfig);
        vm.stopPrank();
    }

    function getCallCount(string memory functionName) external view returns (uint256) {
        return calls[keccak256(bytes(functionName))];
    }
}

contract StableERC4626For4626InvariantTest is StdInvariant, Test {
    StableERC4626For4626 public stable4626;
    MockStableERC4626 public thirdPool;
    MockERC20 public underlying;
    address public admin;
    StableERC4626For4626Handler public handler;

    function setUp() public {
        admin = vm.addr(999);
        underlying = new MockERC20("USDC", "USDC", 6);
        thirdPool = new MockStableERC4626(underlying);

        address implementation = address(new StableERC4626For4626());
        stable4626 = StableERC4626For4626(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        StableERC4626For4626.initialize.selector,
                        admin,
                        address(thirdPool),
                        StakingBuffer.BufferConfig({minimumBuffer: 1000e6, maximumBuffer: 10000e6, buffer: 5000e6})
                    )
                )
            )
        );

        handler = new StableERC4626For4626Handler(stable4626, thirdPool, underlying, admin);

        // Set handler as target for invariant testing
        targetContract(address(handler));

        // Define function selectors to call during invariant testing
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.redeem.selector;
        selectors[3] = handler.mint.selector;
        selectors[4] = handler.simulateYield.selector;
        selectors[5] = handler.withdrawIncomeAssets.selector;
        selectors[6] = handler.updateBufferConfig.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // INVARIANT 1: Total assets should always equal total supply (stable 1:1 ratio)
    function invariant_totalAssetsEqualsSupply() public view {
        assertEq(stable4626.totalAssets(), stable4626.totalSupply(), "Total assets should equal total supply");
    }

    // INVARIANT 2: Conversion functions should maintain 1:1 ratio for stable vault
    function invariant_conversionRatio() public view {
        uint256 testAmount = 1000e6;
        assertEq(stable4626.convertToShares(testAmount), testAmount, "convertToShares should return 1:1 ratio");
        assertEq(stable4626.convertToAssets(testAmount), testAmount, "convertToAssets should return 1:1 ratio");
    }

    // INVARIANT 3: Total tracked assets should equal actual balances
    function invariant_balanceConsistency() public view {
        uint256 underlyingBalance = underlying.balanceOf(address(stable4626));
        uint256 thirdPoolShares = thirdPool.balanceOf(address(stable4626));
        uint256 thirdPoolAssets = thirdPool.previewRedeem(thirdPoolShares);
        uint256 totalSupply = stable4626.totalSupply();
        uint256 totalIncomeAssets = stable4626.totalIncomeAssets();

        // Total balance should be supply + income assets - withdrawn income
        uint256 expectedTotal = totalSupply + totalIncomeAssets;
        uint256 actualTotal = underlyingBalance + thirdPoolAssets + handler.ghost_totalIncomeWithdrawn();

        assertApproxEqAbs(
            expectedTotal,
            actualTotal,
            2, // Allow for 2 unit rounding error due to third pool interactions
            "Balance consistency check failed"
        );
    }

    // INVARIANT 4: Buffer configuration should always be valid
    function invariant_bufferConfigValid() public view {
        (uint256 minBuffer, uint256 maxBuffer, uint256 buffer) = stable4626.bufferConfig();
        
        assertTrue(minBuffer <= maxBuffer, "Minimum buffer should be <= maximum buffer");
        assertTrue(buffer >= minBuffer, "Buffer should be >= minimum buffer");
        assertTrue(buffer <= maxBuffer, "Buffer should be <= maximum buffer");
        assertTrue(minBuffer > 0, "Minimum buffer should be positive");
    }

    // INVARIANT 5: Income assets calculation should be consistent
    function invariant_incomeAssetsConsistency() public view {
        uint256 totalIncomeAssets = stable4626.totalIncomeAssets();
        uint256 underlyingBalance = underlying.balanceOf(address(stable4626));
        uint256 thirdPoolShares = thirdPool.balanceOf(address(stable4626));
        uint256 thirdPoolAssets = thirdPool.previewRedeem(thirdPoolShares);
        uint256 totalSupply = stable4626.totalSupply();
        
        // Income assets should never exceed actual available assets
        uint256 totalAvailableAssets = underlyingBalance + thirdPoolAssets + handler.ghost_totalIncomeWithdrawn();
        assertTrue(
            totalIncomeAssets <= totalAvailableAssets,
            "Income assets should not exceed available assets"
        );
    }

    // INVARIANT 6: Only owner can perform administrative functions
    function invariant_accessControl() public view {
        // Admin should always be the owner
        assertEq(stable4626.owner(), admin, "Admin should remain the owner");
    }

    // INVARIANT 7: Preview functions should be consistent with actual operations
    function invariant_previewFunctionsConsistent() public view {
        uint256 testAmount = 1000e6;
        assertEq(stable4626.previewDeposit(testAmount), testAmount, "previewDeposit should be 1:1");
        assertEq(stable4626.previewMint(testAmount), testAmount, "previewMint should be 1:1");
        assertEq(stable4626.previewWithdraw(testAmount), testAmount, "previewWithdraw should be 1:1");
        assertEq(stable4626.previewRedeem(testAmount), testAmount, "previewRedeem should be 1:1");
    }

    // INVARIANT 8: Ghost variable consistency
    function invariant_ghostVariableConsistency() public view {
        // The difference between minted and burned should equal current total supply
        uint256 netMinted = handler.ghost_mintedSum() >= handler.ghost_burnedSum()
            ? handler.ghost_mintedSum() - handler.ghost_burnedSum()
            : 0;

        // Allow for some tolerance due to potential rounding in operations
        assertApproxEqAbs(
            stable4626.totalSupply(),
            netMinted,
            stable4626.totalSupply() / 1000 + 1, // Allow 0.1% + 1 unit tolerance
            "Ghost variable tracking inconsistent with actual supply"
        );
    }

    // INVARIANT 9: ERC4626 compliance - max functions should return reasonable values
    function invariant_maxFunctionsReasonable() public view {
        address testUser = vm.addr(1);

        // Max functions should not overflow and should be reasonable
        assertTrue(stable4626.maxDeposit(testUser) > 0, "maxDeposit should be positive");
        assertTrue(stable4626.maxMint(testUser) > 0, "maxMint should be positive");

        // If user has balance, max withdraw/redeem should be at least their balance
        uint256 userBalance = stable4626.balanceOf(testUser);
        if (userBalance > 0) {
            assertTrue(stable4626.maxWithdraw(testUser) >= userBalance, "maxWithdraw should be >= user balance");
            assertTrue(stable4626.maxRedeem(testUser) >= userBalance, "maxRedeem should be >= user balance");
        }
    }

    // INVARIANT 10: Third pool interaction consistency
    function invariant_thirdPoolInteractionConsistency() public view {
        uint256 thirdPoolShares = thirdPool.balanceOf(address(stable4626));
        uint256 expectedAssets = thirdPool.previewRedeem(thirdPoolShares);
        
        // The assets we can get from third pool should be reasonable
        if (thirdPoolShares > 0) {
            assertTrue(expectedAssets > 0, "Third pool should provide assets for shares");
        }
    }

    // INVARIANT 11: Underlying asset consistency
    function invariant_underlyingAssetConsistency() public view {
        // The underlying asset should be the same as the third pool's asset
        assertEq(address(stable4626.underlying()), address(underlying), "Underlying should match expected");
        assertEq(stable4626.asset(), address(underlying), "Asset should match underlying");
        assertEq(thirdPool.asset(), address(underlying), "Third pool asset should match underlying");
    }

    // Function to call after invariant testing to check handler call counts
    function invariant_callSummary() public view {
        console.log("=== INVARIANT TEST CALL SUMMARY ===");
        console.log("deposit calls:", handler.getCallCount("deposit"));
        console.log("withdraw calls:", handler.getCallCount("withdraw"));
        console.log("redeem calls:", handler.getCallCount("redeem"));
        console.log("mint calls:", handler.getCallCount("mint"));
        console.log("simulateYield calls:", handler.getCallCount("simulateYield"));
        console.log("withdrawIncomeAssets calls:", handler.getCallCount("withdrawIncomeAssets"));
        console.log("updateBufferConfig calls:", handler.getCallCount("updateBufferConfig"));
        console.log("=== GHOST VARIABLES ===");
        console.log("ghost_depositSum:", handler.ghost_depositSum());
        console.log("ghost_withdrawSum:", handler.ghost_withdrawSum());
        console.log("ghost_mintedSum:", handler.ghost_mintedSum());
        console.log("ghost_burnedSum:", handler.ghost_burnedSum());
        console.log("ghost_totalIncomeWithdrawn:", handler.ghost_totalIncomeWithdrawn());
        console.log("=== CONTRACT STATE ===");
        console.log("totalSupply:", stable4626.totalSupply());
        console.log("totalAssets:", stable4626.totalAssets());
        console.log("totalIncomeAssets:", stable4626.totalIncomeAssets());
        console.log("underlying balance:", underlying.balanceOf(address(stable4626)));
        console.log("third pool shares:", thirdPool.balanceOf(address(stable4626)));
    }
}