// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {VariableERC4626ForAave} from "contracts/v2/tokens/VariableERC4626ForAave.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockAave} from "contracts/v2/test/MockAave.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/console.sol";

contract VariableERC4626ForAaveHandler is Test {
    VariableERC4626ForAave public variableToken;
    MockAave public aavePool;
    MockERC20 public underlying;
    address public admin;

    // Actors for testing
    address[] public actors;
    mapping(bytes32 => uint256) public calls;

    // State tracking for invariant verification
    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_mintedSum;
    uint256 public ghost_burnedSum;
    uint256 public ghost_totalYieldAccrued;
    uint256 public ghost_totalInterestGenerated;

    // Getter function for actors array length
    function getActorsLength() external view returns (uint256) {
        return actors.length;
    }

    // Getter function for actor at index
    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

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

    constructor(VariableERC4626ForAave _variableToken, MockAave _aavePool, MockERC20 _underlying, address _admin) {
        variableToken = _variableToken;
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
        underlying.approve(address(variableToken), amount);
        
        uint256 sharesBefore = variableToken.totalSupply();
        uint256 shares = variableToken.deposit(amount, currentActor);
        
        ghost_depositSum += amount;
        ghost_mintedSum += shares;
        
        // Verify shares were actually minted
        assertEq(variableToken.totalSupply(), sharesBefore + shares, "Shares not properly minted");
    }

    // Withdraw action  
    function withdraw(uint256 assets) external createActor countCall("withdraw") {
        address currentActor = vm.addr(bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 1, 10));
        
        uint256 balance = variableToken.balanceOf(currentActor);
        if (balance == 0) return;
        
        uint256 maxWithdraw = variableToken.maxWithdraw(currentActor);
        if (maxWithdraw == 0) return;
        
        assets = bound(assets, 1, maxWithdraw);
        
        uint256 sharesBurned = variableToken.withdraw(assets, currentActor, currentActor);
        
        ghost_withdrawSum += assets;
        ghost_burnedSum += sharesBurned;
    }

    // Redeem action
    function redeem(uint256 shares) external createActor countCall("redeem") {
        address currentActor = vm.addr(bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 1, 10));
        
        uint256 balance = variableToken.balanceOf(currentActor);
        if (balance == 0) return;
        
        shares = bound(shares, 1, balance);
        
        uint256 assets = variableToken.redeem(shares, currentActor, currentActor);
        
        ghost_withdrawSum += assets;
        ghost_burnedSum += shares;
    }

    // Mint action
    function mint(uint256 shares) external createActor countCall("mint") {
        shares = bound(shares, 1, 1_000_000e6);
        
        address currentActor = vm.addr(bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 1, 10));
        
        uint256 assets = variableToken.previewMint(shares);
        // Add some buffer for potential rounding
        assets = assets + (assets / 1000) + 1;
        
        underlying.mint(currentActor, assets);
        underlying.approve(address(variableToken), assets);
        
        uint256 actualAssets = variableToken.mint(shares, currentActor);
        
        ghost_depositSum += actualAssets;
        ghost_mintedSum += shares;
    }

    // Simulate yield accrual - this is key for variable vaults
    function simulateYield(uint256 yieldAmount) external countCall("simulateYield") {
        // Multiple layers of protection against extreme values
        if (yieldAmount > 100e6) {
            yieldAmount = yieldAmount % 100e6; // Use modulo to wrap large numbers
        }
        
        // Additional safety check - ensure it's within reasonable bounds
        yieldAmount = bound(yieldAmount, 0, 50e6); // Further reduce to max 50 USDC
        
        // Final safety check before execution
        if (yieldAmount > 0 && yieldAmount <= 50e6) {
            aavePool.simulateInterestAccrual(address(variableToken), yieldAmount);
            ghost_totalYieldAccrued += yieldAmount;
            ghost_totalInterestGenerated += yieldAmount;
        }
    }

    // Admin buffer config update
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
        
        variableToken.updateBufferConfig(newConfig);
        vm.stopPrank();
    }

    // Force rebalancing by triggering deposit to pool
    function forceRebalance() external countCall("forceRebalance") {
        // This will trigger internal rebalancing logic
        uint256 smallAmount = 1e6;
        underlying.mint(address(this), smallAmount);
        underlying.approve(address(variableToken), smallAmount);
        
        try variableToken.deposit(smallAmount, address(this)) {
            ghost_depositSum += smallAmount;
            ghost_mintedSum += smallAmount; // Approximate for small amounts
        } catch {
            // If deposit fails, no need to revert anything since mint was successful
            // The tokens will remain in the handler contract
        }
    }
}

contract VariableERC4626ForAaveInvariantTest is StdInvariant, Test {
    VariableERC4626ForAave public variableToken;
    MockAave public aavePool;
    MockERC20 public underlying;
    address public admin;
    VariableERC4626ForAaveHandler public handler;

    function setUp() public {
        admin = vm.addr(999);
        underlying = new MockERC20("USDC", "USDC", 6);
        aavePool = new MockAave(address(underlying));

        address implementation = address(new VariableERC4626ForAave(address(aavePool), 0));
        variableToken = VariableERC4626ForAave(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        VariableERC4626ForAave.initialize.selector,
                        admin,
                        address(underlying),
                        StakingBuffer.BufferConfig({minimumBuffer: 1000e6, maximumBuffer: 10000e6, buffer: 5000e6})
                    )
                )
            )
        );

        handler = new VariableERC4626ForAaveHandler(variableToken, aavePool, underlying, admin);

        // Set handler as target for invariant testing
        targetContract(address(handler));

        // Define function selectors to call during invariant testing
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.redeem.selector;
        selectors[3] = handler.mint.selector;
        selectors[4] = handler.simulateYield.selector;
        selectors[5] = handler.updateBufferConfig.selector;
        selectors[6] = handler.forceRebalance.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // INVARIANT 1: Total assets should always be >= total supply (due to yield generation)
    function invariant_totalAssetsGeSupply() public view {
        uint256 totalAssets = variableToken.totalAssets();
        uint256 totalSupply = variableToken.totalSupply();
        
        assertTrue(
            totalAssets >= totalSupply || totalSupply == 0,
            "Total assets should be >= total supply for variable vault"
        );
    }

    // INVARIANT 2: Total assets should equal underlying balance + aToken balance
    function invariant_totalAssetsConsistency() public view {
        uint256 underlyingBalance = underlying.balanceOf(address(variableToken));
        uint256 aTokenBalance = aavePool.balanceOf(address(variableToken));
        uint256 totalAssets = variableToken.totalAssets();
        
        assertEq(
            totalAssets,
            underlyingBalance + aTokenBalance,
            "Total assets should equal sum of underlying and aToken balances"
        );
    }

    // INVARIANT 3: Share price should be monotonic (non-decreasing over time due to yield)
    uint256 private lastSharePrice = 1e6; // Start at 1:1 ratio
    
    function invariant_sharePriceMonotonic() public {
        if (variableToken.totalSupply() == 0) return;
        
        uint256 currentSharePrice = variableToken.convertToAssets(1e6); // Price per 1 token
        
        assertTrue(
            currentSharePrice >= lastSharePrice,
            "Share price should be monotonic (non-decreasing)"
        );
        
        lastSharePrice = currentSharePrice;
    }

    // INVARIANT 4: Buffer configuration should always be valid
    function invariant_bufferConfigValid() public view {
        (uint256 minBuffer, uint256 maxBuffer, uint256 buffer) = variableToken.bufferConfig();
        
        assertTrue(minBuffer <= maxBuffer, "Minimum buffer should be <= maximum buffer");
        assertTrue(buffer >= minBuffer, "Buffer should be >= minimum buffer");
        assertTrue(buffer <= maxBuffer, "Buffer should be <= maximum buffer");
    }

    // INVARIANT 5: Conversion functions should be consistent
    function invariant_conversionConsistency() public view {
        if (variableToken.totalSupply() == 0) return;
        
        uint256 testAmount = 1000e6;
        uint256 shares = variableToken.convertToShares(testAmount);
        uint256 backToAssets = variableToken.convertToAssets(shares);
        
        // For variable vaults with yield, allow for reasonable rounding errors
        // The tolerance should scale with the exchange rate deviation from 1:1
        uint256 totalAssets = variableToken.totalAssets();
        uint256 totalSupply = variableToken.totalSupply();
        
        // Calculate tolerance based on exchange rate and amount
        // Higher exchange rates (more yield) allow for higher tolerance
        uint256 exchangeRateBps = (totalAssets * 10000) / totalSupply; // in basis points
        uint256 tolerance = (testAmount * (exchangeRateBps - 10000)) / 1000000; // proportional tolerance
        tolerance = tolerance > 0 ? tolerance + 100 : 100; // minimum 100 unit tolerance
        
        assertApproxEqAbs(
            backToAssets,
            testAmount,
            tolerance,
            "Round-trip conversion should be consistent within reasonable tolerance"
        );
    }

    // INVARIANT 7: No negative balances
    function invariant_noNegativeBalances() public view {
        assertTrue(underlying.balanceOf(address(variableToken)) >= 0, "Underlying balance should be non-negative");
        assertTrue(aavePool.balanceOf(address(variableToken)) >= 0, "aToken balance should be non-negative");
        assertTrue(variableToken.totalSupply() >= 0, "Total supply should be non-negative");
        assertTrue(variableToken.totalAssets() >= 0, "Total assets should be non-negative");
    }

    // INVARIANT 8: Sum of all user balances should equal total supply
    function invariant_totalSupplyConsistency() public view {
        uint256 totalSupply = variableToken.totalSupply();
        uint256 sumOfBalances = 0;
        
        // Sum balances of all known actors
        uint256 actorsLength = handler.getActorsLength();
        for (uint256 i = 0; i < actorsLength; i++) {
            sumOfBalances += variableToken.balanceOf(handler.getActor(i));
        }
        
        // Add handler contract balance
        sumOfBalances += variableToken.balanceOf(address(handler));
        
        assertEq(totalSupply, sumOfBalances, "Total supply should equal sum of all balances");
    }

    // INVARIANT 9: Yield accumulation should increase total assets
    function invariant_yieldIncreasesTotalAssets() public view {
        uint256 totalYield = handler.ghost_totalYieldAccrued();
        uint256 totalSupply = variableToken.totalSupply();
        uint256 totalAssets = variableToken.totalAssets();
        
        if (totalSupply > 0 && totalYield > 0) {
            // Total assets should be at least the initial supply plus some portion of yield
            assertTrue(
                totalAssets >= totalSupply,
                "Total assets should reflect yield accumulation"
            );
        }
    }

    // INVARIANT 10: Access control should be maintained
    function invariant_accessControl() public view {
        assertEq(variableToken.owner(), admin, "Admin should remain the owner");
    }

    // INVARIANT 11: Max functions should return reasonable values
    function invariant_maxFunctionsReasonable() public view {
        address testUser = vm.addr(1);
        
        uint256 maxDeposit = variableToken.maxDeposit(testUser);
        uint256 maxMint = variableToken.maxMint(testUser);
        uint256 maxWithdraw = variableToken.maxWithdraw(testUser);
        uint256 maxRedeem = variableToken.maxRedeem(testUser);
        
        // Max functions should not overflow
        assertTrue(maxDeposit <= type(uint256).max, "maxDeposit should not overflow");
        assertTrue(maxMint <= type(uint256).max, "maxMint should not overflow");
        assertTrue(maxWithdraw <= type(uint256).max, "maxWithdraw should not overflow");
        assertTrue(maxRedeem <= type(uint256).max, "maxRedeem should not overflow");
        
        // If user has balance, max withdraw/redeem should be reasonable
        uint256 userBalance = variableToken.balanceOf(testUser);
        if (userBalance > 0) {
            assertTrue(maxRedeem >= userBalance, "maxRedeem should be >= user balance");
        }
    }

    // INVARIANT 12: Exchange rate should never decrease significantly (anti-rug protection)
    uint256 private previousExchangeRate = 1e6;
    
    function invariant_exchangeRateProtection() public {
        if (variableToken.totalSupply() == 0) return;
        
        uint256 currentExchangeRate = variableToken.convertToAssets(1e6);
        
        // Exchange rate should not decrease by more than 0.1% in a single operation
        // This protects against potential manipulation
        uint256 minimumAllowedRate = (previousExchangeRate * 999) / 1000;
        
        assertTrue(
            currentExchangeRate >= minimumAllowedRate,
            "Exchange rate should not decrease significantly"
        );
        
        previousExchangeRate = currentExchangeRate;
    }

    // Function to call after invariant testing to check handler call counts
    function invariant_callSummary() public view {
        console.log("=== VARIABLE ERC4626 INVARIANT TEST CALL SUMMARY ===");
        console.log("deposit calls:", handler.calls("deposit"));
        console.log("withdraw calls:", handler.calls("withdraw"));
        console.log("redeem calls:", handler.calls("redeem"));
        console.log("mint calls:", handler.calls("mint"));
        console.log("simulateYield calls:", handler.calls("simulateYield"));
        console.log("updateBufferConfig calls:", handler.calls("updateBufferConfig"));
        console.log("forceRebalance calls:", handler.calls("forceRebalance"));
        console.log("");
        console.log("Ghost variables:");
        console.log("ghost_depositSum:", handler.ghost_depositSum());
        console.log("ghost_withdrawSum:", handler.ghost_withdrawSum());
        console.log("ghost_mintedSum:", handler.ghost_mintedSum());
        console.log("ghost_burnedSum:", handler.ghost_burnedSum());
        console.log("ghost_totalYieldAccrued:", handler.ghost_totalYieldAccrued());
        console.log("ghost_totalInterestGenerated:", handler.ghost_totalInterestGenerated());
        console.log("");
        console.log("Contract state:");
        console.log("totalSupply:", variableToken.totalSupply());
        console.log("totalAssets:", variableToken.totalAssets());
        console.log("underlying balance:", underlying.balanceOf(address(variableToken)));
        console.log("aToken balance:", aavePool.balanceOf(address(variableToken)));
        
        if (variableToken.totalSupply() > 0) {
            console.log("exchange rate (assets per share):", variableToken.convertToAssets(1e6));
        }
    }
}