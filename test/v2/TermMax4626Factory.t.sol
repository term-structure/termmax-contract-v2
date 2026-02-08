// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TermMax4626Factory} from "contracts/v2/factory/TermMax4626Factory.sol";
import {StableERC4626For4626} from "contracts/v2/tokens/StableERC4626For4626.sol";
import {StableERC4626ForAave} from "contracts/v2/tokens/StableERC4626ForAave.sol";
import {VariableERC4626ForAave} from "contracts/v2/tokens/VariableERC4626ForAave.sol";
import {StableERC4626ForVenus} from "contracts/v2/tokens/StableERC4626ForVenus.sol";
import {StableERC4626ForCustomize} from "contracts/v2/tokens/StableERC4626ForCustomize.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockAave} from "contracts/v2/test/MockAave.sol";
import {MockVToken} from "contracts/mocks/MockVToken.sol";
import {IAaveV3Pool} from "contracts/v2/extensions/aave/IAaveV3Pool.sol";
import {ERC4626TokenEvents} from "contracts/v2/events/ERC4626TokenEvents.sol";
import {FactoryEventsV2} from "contracts/v2/events/FactoryEventsV2.sol";

contract TermMax4626FactoryTest is Test {
    TermMax4626Factory public factory;
    MockERC20 public underlying;
    MockERC4626 public thirdPool;
    MockAave public aavePool;
    MockVToken public venusPool;
    MockERC20 public stableDebtToken;
    MockERC20 public variableDebtToken;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    address public customizePool = makeAddr("customizePool");

    StableERC4626For4626 public impl4626;
    StableERC4626ForAave public implStableAave;
    StableERC4626ForVenus public implVenus;
    VariableERC4626ForAave public implVariableAave;
    StableERC4626ForCustomize public implCustomize;

    StakingBuffer.BufferConfig public defaultBufferConfig;

    function setUp() public {
        // Deploy mocks
        underlying = new MockERC20("USDC", "USDC", 18);
        thirdPool = new MockERC4626(underlying);
        aavePool = new MockAave(address(underlying));
        venusPool = new MockVToken(address(underlying), "vToken", "vToken");

        // MockAave is both the pool and the aToken, and has 18 decimals by default
        // aToken = account(aavePool);

        stableDebtToken = new MockERC20("sUSDC", "sUSDC", 18);
        variableDebtToken = new MockERC20("vUSDC", "vUSDC", 18);

        // Setup Aave pool reserve data - MockAave hardcodes this logic
        // But we need to ensure the factory points to the mock pool

        // Deploy implementations
        impl4626 = new StableERC4626For4626();
        implStableAave = new StableERC4626ForAave(address(aavePool), 100);
        implVariableAave = new VariableERC4626ForAave(address(aavePool), 100);
        implVenus = new StableERC4626ForVenus();
        implCustomize = new StableERC4626ForCustomize();

        // Deploy factory
        factory = new TermMax4626Factory(
            admin,
            address(impl4626),
            address(implStableAave),
            address(implVenus),
            address(implVariableAave),
            address(implCustomize)
        );

        // Setup default buffer config
        defaultBufferConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 1000e18, maximumBuffer: 10000e18, buffer: 5000e18});

        // Labels for better test output
        vm.label(address(factory), "TermMax4626Factory");
        vm.label(address(underlying), "USDC");
        vm.label(address(thirdPool), "ThirdPool");
        vm.label(address(aavePool), "AavePool");
        vm.label(address(venusPool), "VenusPool");
        vm.label(admin, "Admin");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
    }

    function testFactoryInitialization() public {
        // Check that implementation contracts are deployed
        assertTrue(factory.stableERC4626For4626Implementation() != address(0));
        assertTrue(factory.stableERC4626ForAaveImplementation() != address(0));
        assertTrue(factory.variableERC4626ForAaveImplementation() != address(0));
    }

    function testCreateStableERC4626For4626() public {
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.StableERC4626For4626Created(address(this), address(0));

        StableERC4626For4626 vault = factory.createStableERC4626For4626(admin, address(thirdPool), defaultBufferConfig);

        assertTrue(address(vault) != address(0));

        // Verify the vault is properly initialized
        assertEq(vault.owner(), admin);
        assertEq(address(vault.thirdPool()), address(thirdPool));
        assertEq(address(vault.underlying()), address(underlying));
        assertEq(vault.asset(), address(underlying));
        assertEq(vault.name(), "TermMax Stable ERC4626 USDC");
        assertEq(vault.symbol(), "tmseUSDC");

        // Check buffer config
        (uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer) = vault.bufferConfig();
        assertEq(minimumBuffer, defaultBufferConfig.minimumBuffer);
        assertEq(maximumBuffer, defaultBufferConfig.maximumBuffer);
        assertEq(buffer, defaultBufferConfig.buffer);
    }

    function testCreateStableERC4626ForAave() public {
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.StableERC4626ForAaveCreated(address(this), address(0));

        StableERC4626ForAave vault = factory.createStableERC4626ForAave(admin, address(underlying), defaultBufferConfig);

        assertTrue(address(vault) != address(0));

        // Verify the vault is properly initialized
        assertEq(vault.owner(), admin);
        assertEq(address(vault.underlying()), address(underlying));
        assertEq(address(vault.aToken()), address(aavePool));
        assertEq(vault.asset(), address(underlying));
        assertEq(vault.name(), "TermMax Stable AaveERC4626 USDC");
        assertEq(vault.symbol(), "tmsaUSDC");

        // Check buffer config
        (uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer) = vault.bufferConfig();
        assertEq(minimumBuffer, defaultBufferConfig.minimumBuffer);
        assertEq(maximumBuffer, defaultBufferConfig.maximumBuffer);
        assertEq(buffer, defaultBufferConfig.buffer);
    }

    function testCreateVariableERC4626ForAave() public {
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.VariableERC4626ForAaveCreated(address(this), address(0));

        VariableERC4626ForAave vault =
            factory.createVariableERC4626ForAave(admin, address(underlying), defaultBufferConfig);

        assertTrue(address(vault) != address(0));

        // Verify the vault is properly initialized
        assertEq(vault.owner(), admin);
        assertEq(address(vault.underlying()), address(underlying));
        assertEq(address(vault.aToken()), address(aavePool));
        assertEq(vault.asset(), address(underlying));
        assertEq(vault.name(), "TermMax Variable AaveERC4626 USDC");
        assertEq(vault.symbol(), "tmvaUSDC");

        // Check buffer config
        (uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer) = vault.bufferConfig();
        assertEq(minimumBuffer, defaultBufferConfig.minimumBuffer);
        assertEq(maximumBuffer, defaultBufferConfig.maximumBuffer);
        assertEq(buffer, defaultBufferConfig.buffer);
    }

    function testCreateMultipleVaultsWithSameParameters() public {
        // Create first vault
        StableERC4626For4626 vault1 = factory.createStableERC4626For4626(admin, address(thirdPool), defaultBufferConfig);

        // Create second vault with same parameters
        StableERC4626For4626 vault2 = factory.createStableERC4626For4626(admin, address(thirdPool), defaultBufferConfig);

        // Should create different addresses
        assertTrue(address(vault1) != address(vault2));
        assertTrue(address(vault1) != address(0));
        assertTrue(address(vault2) != address(0));

        // Both should be properly initialized
        assertEq(vault1.owner(), admin);
        assertEq(vault2.owner(), admin);
        assertEq(address(vault1.thirdPool()), address(thirdPool));
        assertEq(address(vault2.thirdPool()), address(thirdPool));
    }

    function testCreateVaultsWithDifferentAdmins() public {
        StableERC4626For4626 vault1 = factory.createStableERC4626For4626(admin, address(thirdPool), defaultBufferConfig);

        StableERC4626For4626 vault2 = factory.createStableERC4626For4626(user1, address(thirdPool), defaultBufferConfig);

        assertEq(vault1.owner(), admin);
        assertEq(vault2.owner(), user1);
    }

    function testCreateVaultsWithDifferentBufferConfigs() public {
        StakingBuffer.BufferConfig memory config1 =
            StakingBuffer.BufferConfig({minimumBuffer: 500e18, maximumBuffer: 5000e18, buffer: 2500e18});

        StakingBuffer.BufferConfig memory config2 =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e18, maximumBuffer: 20000e18, buffer: 10000e18});

        StableERC4626For4626 vault1 = factory.createStableERC4626For4626(admin, address(thirdPool), config1);
        StableERC4626For4626 vault2 = factory.createStableERC4626For4626(admin, address(thirdPool), config2);

        (uint256 min1, uint256 max1, uint256 buf1) = vault1.bufferConfig();
        (uint256 min2, uint256 max2, uint256 buf2) = vault2.bufferConfig();

        assertEq(min1, config1.minimumBuffer);
        assertEq(max1, config1.maximumBuffer);
        assertEq(buf1, config1.buffer);

        assertEq(min2, config2.minimumBuffer);
        assertEq(max2, config2.maximumBuffer);
        assertEq(buf2, config2.buffer);
    }

    function testCreateWithZeroAddressAdmin() public {
        vm.expectRevert();
        factory.createStableERC4626For4626(address(0), address(thirdPool), defaultBufferConfig);
    }

    function testCreateStableERC4626For4626WithZeroThirdPool() public {
        vm.expectRevert();
        factory.createStableERC4626For4626(admin, address(0), defaultBufferConfig);
    }

    function testCreateStableERC4626ForAaveWithZeroUnderlying() public {
        vm.expectRevert();
        factory.createStableERC4626ForAave(admin, address(0), defaultBufferConfig);
    }

    function testCreateVariableERC4626ForAaveWithZeroUnderlying() public {
        vm.expectRevert();
        factory.createVariableERC4626ForAave(admin, address(0), defaultBufferConfig);
    }

    function testCreateWithInvalidBufferConfig() public {
        // Test minimum buffer greater than maximum buffer
        StakingBuffer.BufferConfig memory invalidConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 10000e18, maximumBuffer: 5000e18, buffer: 7500e18});

        vm.expectRevert();
        factory.createStableERC4626For4626(admin, address(thirdPool), invalidConfig);

        // Test buffer outside min/max range (below minimum)
        invalidConfig = StakingBuffer.BufferConfig({minimumBuffer: 5000e18, maximumBuffer: 10000e18, buffer: 4000e18});

        vm.expectRevert();
        factory.createStableERC4626For4626(admin, address(thirdPool), invalidConfig);

        // Test buffer outside min/max range (above maximum)
        invalidConfig = StakingBuffer.BufferConfig({minimumBuffer: 5000e18, maximumBuffer: 10000e18, buffer: 11000e18});

        vm.expectRevert();
        factory.createStableERC4626For4626(admin, address(thirdPool), invalidConfig);
    }

    function testEventEmissions() public {
        // Test StableERC4626For4626Created event
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.StableERC4626For4626Created(address(this), address(0));
        StableERC4626For4626 vault1 = factory.createStableERC4626For4626(admin, address(thirdPool), defaultBufferConfig);

        // Test StableERC4626ForAaveCreated event
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.StableERC4626ForAaveCreated(address(this), address(0));
        StableERC4626ForAave vault2 =
            factory.createStableERC4626ForAave(admin, address(underlying), defaultBufferConfig);

        // Test VariableERC4626ForAaveCreated event
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.VariableERC4626ForAaveCreated(address(this), address(0));
        VariableERC4626ForAave vault3 =
            factory.createVariableERC4626ForAave(admin, address(underlying), defaultBufferConfig);

        // Verify all vaults were created
        assertTrue(address(vault1) != address(0));
        assertTrue(address(vault2) != address(0));
        assertTrue(address(vault3) != address(0));
    }

    function testImplementationAddresses() public {
        address impl1 = factory.stableERC4626For4626Implementation();
        address impl2 = factory.stableERC4626ForAaveImplementation();
        address impl3 = factory.variableERC4626ForAaveImplementation();
        address impl4 = factory.stableERC4626ForVenusImplementation();
        address impl5 = factory.stableERC4626ForCustomizeImplementation();

        // All implementations should be deployed
        assertTrue(impl1 != address(0));
        assertTrue(impl2 != address(0));
        assertTrue(impl3 != address(0));
        assertTrue(impl4 != address(0));
        assertTrue(impl5 != address(0));

        // Implementations should have code
        assertTrue(impl1.code.length > 0);
        assertTrue(impl2.code.length > 0);
        assertTrue(impl3.code.length > 0);
        assertTrue(impl4.code.length > 0);
        assertTrue(impl5.code.length > 0);
    }

    function testVaultFunctionality() public {
        // Create a vault and test basic functionality
        StableERC4626For4626 stableVault =
            factory.createStableERC4626For4626(admin, address(thirdPool), defaultBufferConfig);

        // Mint some underlying tokens
        uint256 amount = 1000e18;
        underlying.mint(user1, amount);

        // Test deposit
        vm.startPrank(user1);
        underlying.approve(address(stableVault), amount);
        stableVault.deposit(amount, user1);
        vm.stopPrank();

        // Verify deposit worked
        assertEq(stableVault.balanceOf(user1), amount);
        assertEq(underlying.balanceOf(user1), 0);

        // Test withdraw
        vm.startPrank(user1);
        stableVault.redeem(amount, user1, user1);
        vm.stopPrank();

        // Verify withdraw worked
        assertEq(stableVault.balanceOf(user1), 0);
        assertEq(underlying.balanceOf(user1), amount);
    }

    function testGasUsage() public {
        uint256 gasBefore = gasleft();
        factory.createStableERC4626For4626(admin, address(thirdPool), defaultBufferConfig);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (adjust threshold as needed)
        assertLt(gasUsed, 2_000_000);
        emit log_named_uint("Gas used for createStableERC4626For4626", gasUsed);

        gasBefore = gasleft();
        factory.createStableERC4626ForAave(admin, address(underlying), defaultBufferConfig);
        gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 2_000_000);
        emit log_named_uint("Gas used for createStableERC4626ForAave", gasUsed);

        gasBefore = gasleft();
        factory.createVariableERC4626ForAave(admin, address(underlying), defaultBufferConfig);
        gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 2_000_000);
        emit log_named_uint("Gas used for createVariableERC4626ForAave", gasUsed);
    }

    function testCreateVaultWithExtremeTotalSupply() public {
        // Test with underlying token that has extreme total supply
        MockERC20 extremeToken = new MockERC20("EXTREME", "EXT", 18);
        extremeToken.mint(address(this), type(uint256).max / 2);

        MockERC4626 extremePool = new MockERC4626(extremeToken);

        // Setup Aave reserve data for extreme token
        // MockAave automatically handles any token as if it were the pool token itself, so no setup needed
        // Note: this implies aTokenAddress == address(aavePool) which is fine for this test which only checks creation

        // Create appropriate buffer config for 18 decimal token
        StakingBuffer.BufferConfig memory extremeBufferConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 1000e18, maximumBuffer: 10000e18, buffer: 5000e18});

        // Should still be able to create vaults
        StableERC4626For4626 vault1 =
            factory.createStableERC4626For4626(admin, address(extremePool), extremeBufferConfig);
        StableERC4626ForAave vault2 =
            factory.createStableERC4626ForAave(admin, address(extremeToken), extremeBufferConfig);

        assertTrue(address(vault1) != address(0));
        assertTrue(address(vault2) != address(0));
    }

    function testCreateStableERC4626ForVenus() public {
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.StableERC4626ForVenusCreated(address(this), address(0));

        StableERC4626ForVenus vault =
            factory.createStableERC4626ForVenus(admin, address(venusPool), defaultBufferConfig);

        assertTrue(address(vault) != address(0));
        assertEq(vault.owner(), admin);
        assertEq(address(vault.thirdPool()), address(venusPool));
        assertEq(address(vault.underlying()), address(underlying));
    }

    function testCreateStableERC4626ForCustomize() public {
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.StableERC4626ForCustomizeCreated(address(this), address(0));

        StableERC4626ForCustomize vault =
            factory.createStableERC4626ForCustomize(admin, customizePool, address(underlying), defaultBufferConfig);

        assertTrue(address(vault) != address(0));
        assertEq(vault.owner(), admin);
        assertEq(vault.thirdPool(), customizePool);
        assertEq(address(vault.underlying()), address(underlying));
    }

    function testCreateVariableAndStableERC4626ForAave() public {
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.VariableERC4626ForAaveCreated(address(this), address(0));
        vm.expectEmit(true, false, false, false);
        emit FactoryEventsV2.StableERC4626ForAaveCreated(address(this), address(0));

        (VariableERC4626ForAave vImpl, StableERC4626ForAave sImpl) =
            factory.createVariableAndStableERC4626ForAave(admin, address(underlying), defaultBufferConfig);

        assertTrue(address(vImpl) != address(0));
        assertTrue(address(sImpl) != address(0));
        assertEq(vImpl.owner(), admin);
        assertEq(sImpl.owner(), admin);
    }
}
