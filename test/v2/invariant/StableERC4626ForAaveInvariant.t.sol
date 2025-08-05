// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StableERC4626ForAave} from "contracts/v2/tokens/StableERC4626ForAave.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockAave} from "contracts/v2/test/MockAave.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/console.sol";

contract StableERC4626ForAaveHandler is Test {
    StableERC4626ForAave public stable4626;
    MockAave public aavePool;
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

    constructor(StableERC4626ForAave _stable4626, MockAave _aavePool, MockERC20 _underlying, address _admin) {
        stable4626 = _stable4626;
        aavePool = _aavePool;
        underlying = _underlying;
        admin = _admin;

        // Create actors for testing
        for (uint256 i = 0; i < 10; i++) {
            actors.push(vm.addr(i + 1));
        }
    }

    // Deposit action
    function deposit(uint256 amount) external createActor countCall("deposit") {
        amount = bound(amount, 1, 1_000_000e6); // Bound to reasonable range

        address currentActor = vm.addr(bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 1, 10));

        // Ensure actor has enough tokens
        underlying.mint(currentActor, amount);
        underlying.approve(address(stable4626), amount);

        uint256 shares = stable4626.deposit(amount, currentActor);

        ghost_depositSum += amount;
        ghost_mintedSum += shares;
    }

    // Withdraw action
    function withdraw(uint256 amount) external createActor countCall("withdraw") {
        address currentActor = vm.addr(bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 1, 10));

        uint256 balance = stable4626.balanceOf(currentActor);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        uint256 assets = stable4626.redeem(amount, currentActor, currentActor);

        ghost_withdrawSum += assets;
        ghost_burnedSum += amount;
    }

    // Redeem action
    function redeem(uint256 shares) external createActor countCall("redeem") {
        address currentActor = vm.addr(bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 1, 10));

        uint256 balance = stable4626.balanceOf(currentActor);
        if (balance == 0) return;

        shares = bound(shares, 1, balance);

        uint256 assets = stable4626.redeem(shares, currentActor, currentActor);

        ghost_withdrawSum += assets;
        ghost_burnedSum += shares;
    }

    // Mint action
    function mint(uint256 shares) external createActor countCall("mint") {
        shares = bound(shares, 1, 1_000_000e6);

        address currentActor = vm.addr(bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 1, 10));

        uint256 assets = stable4626.previewMint(shares);
        underlying.mint(currentActor, assets);
        underlying.approve(address(stable4626), assets);

        stable4626.mint(shares, currentActor);

        ghost_depositSum += assets;
        ghost_mintedSum += shares;
    }

    // Burn to aToken action
    function burnToAToken(uint256 amount) external createActor countCall("burnToAToken") {
        address currentActor = vm.addr(bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 1, 10));

        uint256 balance = stable4626.balanceOf(currentActor);
        if (balance == 0) return;

        // Need sufficient aToken balance in the contract to burn to aToken
        uint256 aTokenBalance = aavePool.balanceOf(address(stable4626));
        if (aTokenBalance == 0) return;

        amount = bound(amount, 1, Math.min(balance, aTokenBalance));

        stable4626.burnToAToken(currentActor, amount);
        ghost_burnedSum += amount;
    }

    // Simulate yield accrual
    function simulateYield(uint256 yieldAmount) external countCall("simulateYield") {
        yieldAmount = bound(yieldAmount, 0, 100e6);
        aavePool.simulateInterestAccrual(address(stable4626), yieldAmount);
    }

    // Admin actions
    function withdrawIncomeAssets(uint256 amount, bool asUnderlying) external countCall("withdrawIncomeAssets") {
        vm.startPrank(admin);

        uint256 totalIncome = stable4626.totalIncomeAssets();
        if (totalIncome == 0) {
            vm.stopPrank();
            return;
        }

        amount = bound(amount, 1, totalIncome);

        address asset = asUnderlying ? address(underlying) : address(aavePool);
        stable4626.withdrawIncomeAssets(asset, admin, amount);

        ghost_totalIncomeWithdrawn += amount;
        vm.stopPrank();
    }

    function updateBufferConfig(uint256 minBuffer, uint256 maxBuffer, uint256 buffer)
        external
        countCall("updateBufferConfig")
    {
        vm.startPrank(admin);

        // Bound to reasonable values and ensure valid configuration
        minBuffer = bound(minBuffer, 100e6, 5000e6);
        maxBuffer = bound(maxBuffer, minBuffer, 50000e6);
        buffer = bound(buffer, minBuffer, maxBuffer);

        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: minBuffer, maximumBuffer: maxBuffer, buffer: buffer});

        stable4626.updateBufferConfigAndAddReserves(0, newConfig);
        vm.stopPrank();
    }
}

contract StableERC4626ForAaveInvariantTest is StdInvariant, Test {
    StableERC4626ForAave public stable4626;
    MockAave public aavePool;
    MockERC20 public underlying;
    address public admin;
    StableERC4626ForAaveHandler public handler;

    function setUp() public {
        admin = vm.addr(999);
        underlying = new MockERC20("USDC", "USDC", 6);
        aavePool = new MockAave(address(underlying));

        address implementation = address(new StableERC4626ForAave(address(aavePool), 0));
        stable4626 = StableERC4626ForAave(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        StableERC4626ForAave.initialize.selector,
                        admin,
                        address(underlying),
                        StakingBuffer.BufferConfig({minimumBuffer: 1000e6, maximumBuffer: 10000e6, buffer: 5000e6})
                    )
                )
            )
        );

        handler = new StableERC4626ForAaveHandler(stable4626, aavePool, underlying, admin);

        // Set handler as target for invariant testing
        targetContract(address(handler));

        // Define function selectors to call during invariant testing
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.redeem.selector;
        selectors[3] = handler.mint.selector;
        selectors[4] = handler.burnToAToken.selector;
        selectors[5] = handler.simulateYield.selector;
        selectors[6] = handler.withdrawIncomeAssets.selector;
        selectors[7] = handler.updateBufferConfig.selector;

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
        uint256 aTokenBalance = aavePool.balanceOf(address(stable4626));
        uint256 totalSupply = stable4626.totalSupply();
        uint256 totalIncomeAssets = stable4626.totalIncomeAssets();

        // Total balance should be supply + income assets - withdrawn income
        uint256 expectedTotal = totalSupply + totalIncomeAssets;
        uint256 actualTotal = underlyingBalance + aTokenBalance + handler.ghost_totalIncomeWithdrawn();

        assertApproxEqAbs(
            expectedTotal,
            actualTotal,
            1, // Allow for 1 unit rounding error
            "Balance consistency check failed"
        );
    }

    // INVARIANT 4: Buffer configuration should always be valid
    function invariant_bufferConfigValid() public view {
        (uint256 minBuffer, uint256 maxBuffer, uint256 buffer) = stable4626.bufferConfig();

        assertTrue(minBuffer <= maxBuffer, "Minimum buffer should be <= maximum buffer");
        assertTrue(buffer >= minBuffer, "Buffer should be >= minimum buffer");
        assertTrue(buffer <= maxBuffer, "Buffer should be <= maximum buffer");
    }

    // INVARIANT 5: Contract should never have negative balances
    function invariant_noNegativeBalances() public view {
        assertTrue(underlying.balanceOf(address(stable4626)) >= 0, "Underlying balance should be non-negative");
        assertTrue(aavePool.balanceOf(address(stable4626)) >= 0, "aToken balance should be non-negative");
        assertTrue(stable4626.totalSupply() >= 0, "Total supply should be non-negative");
    }

    // INVARIANT 6: Total income assets calculation should be consistent
    function invariant_incomeAssetsConsistency() public view {
        uint256 aTokenBalance = aavePool.balanceOf(address(stable4626));
        uint256 underlyingBalance = underlying.balanceOf(address(stable4626));
        uint256 totalSupply = stable4626.totalSupply();
        uint256 withdrawnIncome = handler.ghost_totalIncomeWithdrawn();

        uint256 expectedIncomeAssets = aTokenBalance + underlyingBalance;
        if (expectedIncomeAssets >= totalSupply) {
            expectedIncomeAssets = expectedIncomeAssets - totalSupply + withdrawnIncome;
        } else {
            expectedIncomeAssets = withdrawnIncome;
        }

        uint256 reportedIncomeAssets = stable4626.totalIncomeAssets();

        assertApproxEqAbs(
            reportedIncomeAssets,
            expectedIncomeAssets,
            1, // Allow for 1 unit rounding error
            "Income assets calculation inconsistent"
        );
    }

    // INVARIANT 7: Preview functions should be consistent with actual operations
    function invariant_previewConsistency() public view {
        uint256 testAmount = 1000e6;

        // For stable vault, preview functions should return 1:1
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

    // INVARIANT 9: Access control should be maintained
    function invariant_accessControl() public view {
        // Admin should always be the owner
        assertEq(stable4626.owner(), admin, "Admin should remain the owner");
    }

    // INVARIANT 10: ERC4626 compliance - max functions should return reasonable values
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

    // Function to call after invariant testing to check handler call counts
    function invariant_callSummary() public view {
        console.log("=== INVARIANT TEST CALL SUMMARY ===");
        console.log("deposit calls:", handler.calls("deposit"));
        console.log("withdraw calls:", handler.calls("withdraw"));
        console.log("redeem calls:", handler.calls("redeem"));
        console.log("mint calls:", handler.calls("mint"));
        console.log("burnToAToken calls:", handler.calls("burnToAToken"));
        console.log("simulateYield calls:", handler.calls("simulateYield"));
        console.log("withdrawIncomeAssets calls:", handler.calls("withdrawIncomeAssets"));
        console.log("updateBufferConfig calls:", handler.calls("updateBufferConfig"));
        console.log("");
        console.log("Ghost variables:");
        console.log("ghost_depositSum:", handler.ghost_depositSum());
        console.log("ghost_withdrawSum:", handler.ghost_withdrawSum());
        console.log("ghost_mintedSum:", handler.ghost_mintedSum());
        console.log("ghost_burnedSum:", handler.ghost_burnedSum());
        console.log("ghost_totalIncomeWithdrawn:", handler.ghost_totalIncomeWithdrawn());
        console.log("");
        console.log("Contract state:");
        console.log("totalSupply:", stable4626.totalSupply());
        console.log("totalAssets:", stable4626.totalAssets());
        console.log("totalIncomeAssets:", stable4626.totalIncomeAssets());
        console.log("underlying balance:", underlying.balanceOf(address(stable4626)));
        console.log("aToken balance:", aavePool.balanceOf(address(stable4626)));
    }
}
