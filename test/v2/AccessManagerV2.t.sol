// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {IAccessControl} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {GearingTokenWithERC20} from "contracts/v1/tokens/GearingTokenWithERC20.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {ITermMaxFactory} from "contracts/v1/factory/ITermMaxFactory.sol";
import {MarketConfig, FeeConfig, MarketInitialParams} from "contracts/v1/storage/TermMaxStorage.sol";
import {IOwnable, IPausable, AccessManagerV2, AccessManager} from "contracts/v2/access/AccessManagerV2.sol";
import {TermMaxRouterV2} from "contracts/v2/router/TermMaxRouterV2.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {TermMaxVaultV2} from "contracts/v2/vault/TermMaxVaultV2.sol";
import {ITermMaxVault} from "contracts/v1/vault/ITermMaxVault.sol";
import {Constants} from "contracts/v1/lib/Constants.sol";
import "contracts/v1/storage/TermMaxStorage.sol";
import {IOracleV2} from "contracts/v2/oracle/IOracleV2.sol";
import {VaultInitialParamsV2} from "contracts/v2/storage/TermMaxStorageV2.sol";
import {TermMaxOrderV2} from "contracts/v2/TermMaxOrderV2.sol";
import {ITermMaxVaultV2, OrderV2ConfigurationParams, CurveCuts} from "contracts/v2/vault/ITermMaxVaultV2.sol";
import {VaultEventsV2} from "contracts/v2/events/VaultEventsV2.sol";
import {IWhitelistManager} from "contracts/v2/access/IWhitelistManager.sol";

contract AccessManagerTestV2 is Test {
    using JSONLoader for *;

    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address maker = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;
    AccessManagerV2 manager;
    address curator = vm.randomAddress();
    TermMaxOrderV2 vaultOrder;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order = TermMaxOrderV2(
            address(
                res.market.createOrder(
                    maker, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts
                )
            )
        );

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        uint256 amount = 150e8;
        res.debt.mint(deployer, amount);
        res.debt.approve(address(res.market), amount);
        res.market.mint(deployer, amount);
        res.ft.transfer(address(res.order), amount);
        res.xt.transfer(address(res.order), amount);

        (res.router, res.whitelistManager) = DeployUtils.deployRouter(deployer);
        res.router.setWhitelistManager(address(res.whitelistManager));

        AccessManagerV2 implementation = new AccessManagerV2();
        bytes memory data = abi.encodeCall(AccessManager.initialize, deployer);
        address proxy = address(new ERC1967Proxy(address(implementation), data));

        manager = AccessManagerV2(proxy);

        IOwnable(address(res.factory)).transferOwnership(address(manager));
        IOwnable(address(res.market)).transferOwnership(address(manager));
        IOwnable(address(res.router)).transferOwnership(address(manager));
        IOwnable(address(res.oracle)).transferOwnership(address(manager));
        IOwnable(address(res.whitelistManager)).transferOwnership(address(manager));

        manager.acceptOwnership(IOwnable(address(res.factory)));
        manager.acceptOwnership(IOwnable(address(res.market)));
        manager.acceptOwnership(IOwnable(address(res.router)));
        manager.acceptOwnership(IOwnable(address(res.oracle)));
        manager.acceptOwnership(IOwnable(address(res.whitelistManager)));

        manager.grantRole(manager.CONFIGURATOR_ROLE(), deployer);
        manager.grantRole(manager.PAUSER_ROLE(), deployer);
        manager.grantRole(manager.VAULT_ROLE(), deployer);
        manager.grantRole(manager.MARKET_ROLE(), deployer);
        manager.grantRole(manager.ORACLE_ROLE(), deployer);
        manager.grantRole(manager.WHITELIST_ROLE(), deployer);

        // Create vault initialization parameters
        VaultInitialParamsV2 memory params = VaultInitialParamsV2({
            admin: address(manager),
            curator: curator,
            guardian: address(0), // Will be set through AccessManager
            timelock: 1 days,
            asset: IERC20(address(res.debt)),
            pool: IERC4626(address(0)), // No pool for this test
            maxCapacity: 1000000e18,
            name: "Test Vault",
            symbol: "tVAULT",
            performanceFeeRate: 0.2e8,
            minApy: 0
        });

        // Deploy vault
        res.vault = DeployUtils.deployVault(params);
        vm.stopPrank();

        vm.startPrank(curator);
        res.vault.submitMarket(address(res.market), true);
        vm.warp(block.timestamp + 1 days);
        res.vault.acceptMarket(address(res.market));

        OrderV2ConfigurationParams memory configParams = OrderV2ConfigurationParams({
            maxXtReserve: 1000e18,
            originalVirtualXtReserve: 0,
            virtualXtReserve: 100e18,
            curveCuts: orderConfig.curveCuts
        });

        vaultOrder = TermMaxOrderV2(address(res.vault.createOrder(res.market, configParams)));
        vm.stopPrank();
    }

    function testTransferOwnership() public {
        vm.prank(deployer);
        manager.transferOwnership(IOwnable(address(res.router)), sender);
        vm.prank(sender);
        IOwnable(address(res.router)).acceptOwnership();
        assert(res.router.owner() == sender);
    }

    function testTransferOwnershipWithoutAuth() public {
        vm.prank(sender);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, sender, uint256(0))
        );
        manager.transferOwnership(IOwnable(address(res.router)), sender);
    }

    function testRoleManagement() public {
        address newUser = vm.randomAddress();

        // Test granting roles
        vm.startPrank(deployer);
        manager.grantRole(manager.PAUSER_ROLE(), newUser);
        manager.grantRole(manager.CONFIGURATOR_ROLE(), newUser);
        manager.grantRole(manager.VAULT_ROLE(), newUser);

        assertTrue(manager.hasRole(manager.PAUSER_ROLE(), newUser));
        assertTrue(manager.hasRole(manager.CONFIGURATOR_ROLE(), newUser));
        assertTrue(manager.hasRole(manager.VAULT_ROLE(), newUser));

        // Test revoking roles
        manager.revokeRole(manager.PAUSER_ROLE(), newUser);
        manager.revokeRole(manager.CONFIGURATOR_ROLE(), newUser);
        manager.revokeRole(manager.VAULT_ROLE(), newUser);

        assertFalse(manager.hasRole(manager.PAUSER_ROLE(), newUser));
        assertFalse(manager.hasRole(manager.CONFIGURATOR_ROLE(), newUser));
        assertFalse(manager.hasRole(manager.VAULT_ROLE(), newUser));

        vm.stopPrank();
    }

    function testRevokeRole() public {
        bytes32 pauserRole = manager.PAUSER_ROLE();
        address user = vm.randomAddress();

        // Grant role first
        vm.prank(deployer);
        manager.grantRole(pauserRole, user);

        // Revoke role
        vm.prank(deployer);
        manager.revokeRole(pauserRole, user);

        assertFalse(manager.hasRole(pauserRole, user));
    }

    function testCannotRevokeSelfRole() public {
        bytes32 pauserRole = manager.PAUSER_ROLE();

        // Try to revoke own role
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSignature("AccessControlBadConfirmation()"));
        manager.revokeRole(pauserRole, deployer);
    }

    function testCannotRenounceRole() public {
        bytes32 defaultAdminRole = 0x00;

        vm.prank(deployer);
        vm.expectRevert(AccessManagerV2.CannotRenounceRole.selector);
        manager.renounceRole(defaultAdminRole, deployer);
    }

    function testPausingFunctionality() public {
        address pauser = vm.randomAddress();
        bytes32 pauserRole = manager.PAUSER_ROLE();
        // Grant PAUSER_ROLE to the pauser
        vm.prank(deployer);
        manager.grantRole(pauserRole, pauser);

        // Test pausing with PAUSER_ROLE
        vm.startPrank(pauser);
        manager.setSwitch(IPausable(address(res.router)), false);
        assertTrue(PausableUpgradeable(address(res.router)).paused());

        // Test unpausing with PAUSER_ROLE
        manager.setSwitch(IPausable(address(res.router)), true);
        assertFalse(PausableUpgradeable(address(res.router)).paused());
        vm.stopPrank();

        // Test pausing without PAUSER_ROLE
        address nonPauser = vm.randomAddress();
        vm.startPrank(nonPauser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonPauser, manager.PAUSER_ROLE()
            )
        );
        manager.setSwitch(IPausable(address(res.router)), false);
        vm.stopPrank();
    }

    function testBatchSetSwitch() public {
        address pauser = vm.randomAddress();
        bytes32 pauserRole = manager.PAUSER_ROLE();

        // Create multiple pausable test entities
        IPausable[] memory entities = new IPausable[](2);
        entities[0] = IPausable(address(res.router));
        entities[1] = IPausable(address(res.vault));

        // Grant PAUSER_ROLE to the pauser
        vm.prank(deployer);
        manager.grantRole(pauserRole, pauser);

        // Test batch pausing with PAUSER_ROLE
        vm.startPrank(pauser);
        manager.batchSetSwitch(entities, false);

        // Verify all entities are paused
        assertTrue(PausableUpgradeable(address(res.router)).paused());
        assertTrue(PausableUpgradeable(address(res.vault)).paused());

        // Test batch unpausing with PAUSER_ROLE
        manager.batchSetSwitch(entities, true);

        // Verify all entities are unpaused
        assertFalse(PausableUpgradeable(address(res.router)).paused());
        assertFalse(PausableUpgradeable(address(res.vault)).paused());
        vm.stopPrank();

        // Test batch pausing without PAUSER_ROLE
        address nonPauser = vm.randomAddress();
        vm.startPrank(nonPauser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonPauser, manager.PAUSER_ROLE()
            )
        );
        manager.batchSetSwitch(entities, false);
        vm.stopPrank();
    }

    function testBatchSetWhitelist() public {
        // prepare addresses and module
        address[] memory addrs = new address[](2);
        addrs[0] = vm.randomAddress();
        addrs[1] = vm.randomAddress();
        IWhitelistManager.ContractModule module = IWhitelistManager.ContractModule.ADAPTER;

        // manager has been granted WHITELIST_ROLE in setUp and is owner of whitelistManager
        vm.prank(deployer);
        manager.batchSetWhitelist(IWhitelistManager(address(res.whitelistManager)), addrs, module, true);

        // verify whitelist entries set
        assertTrue(res.whitelistManager.isWhitelisted(addrs[0], module));
        assertTrue(res.whitelistManager.isWhitelisted(addrs[1], module));

        // unset them
        vm.prank(deployer);
        manager.batchSetWhitelist(IWhitelistManager(address(res.whitelistManager)), addrs, module, false);

        assertFalse(res.whitelistManager.isWhitelisted(addrs[0], module));
        assertFalse(res.whitelistManager.isWhitelisted(addrs[1], module));
    }

    function testBatchSetWhitelistWithoutRole() public {
        address[] memory addrs = new address[](1);
        addrs[0] = vm.randomAddress();
        IWhitelistManager.ContractModule module = IWhitelistManager.ContractModule.MARKET;

        address unauthorized = vm.randomAddress();
        vm.startPrank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, manager.WHITELIST_ROLE()
            )
        );
        manager.batchSetWhitelist(IWhitelistManager(address(res.whitelistManager)), addrs, module, true);
        vm.stopPrank();
    }

    function testVaultManagement() public {
        address vaultManager = vm.randomAddress();
        address newCurator = vm.randomAddress();

        // Create vault initialization parameters
        VaultInitialParamsV2 memory params = VaultInitialParamsV2({
            admin: address(manager),
            curator: address(0), // Will be set through AccessManager
            guardian: address(0), // Will be set through AccessManager
            timelock: 1 days,
            asset: IERC20(address(res.debt)),
            pool: IERC4626(address(0)), // No pool for this test
            maxCapacity: 1000000e18,
            name: "Test Vault",
            symbol: "tVAULT",
            performanceFeeRate: 0.2e8, // 20%
            minApy: 0 // 5% minimum APY
        });

        // Deploy vault
        TermMaxVaultV2 vault = DeployUtils.deployVault(params);

        // Grant VAULT_ROLE to the vault manager
        vm.startPrank(deployer);
        manager.grantRole(manager.VAULT_ROLE(), vaultManager);
        vm.stopPrank();

        vm.startPrank(vaultManager);

        // Test setting curator
        manager.setCuratorForVault(ITermMaxVault(address(res.vault)), newCurator);
        assertEq(res.vault.curator(), newCurator);

        vm.stopPrank();

        // Test without VAULT_ROLE
        address nonVaultManager = vm.randomAddress();
        vm.startPrank(nonVaultManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.setCuratorForVault(ITermMaxVault(address(res.vault)), newCurator);
        vm.stopPrank();

        // Test that non-vault role cannot set allocator
        address allocator = vm.randomAddress();
        vm.startPrank(allocator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, allocator, manager.VAULT_ROLE()
            )
        );
        manager.setIsAllocatorForVault(ITermMaxVault(address(res.vault)), allocator, true);
        vm.stopPrank();
    }

    function testRevokeVaultPendingValues() public {
        address newMarket = vm.randomAddress();
        address newGuardian = vm.randomAddress();
        address vaultManager = vm.randomAddress();

        // Grant VAULT_ROLE to the vault manager and set curator
        vm.startPrank(deployer);
        manager.grantRole(manager.VAULT_ROLE(), vaultManager);
        vm.stopPrank();

        vm.startPrank(curator);
        res.vault.submitTimelock(2 days);
        res.vault.submitTimelock(1 days);
        res.vault.submitMarket(newMarket, true);
        vm.stopPrank();

        vm.startPrank(vaultManager);
        manager.setCuratorForVault(ITermMaxVault(address(res.vault)), vaultManager);

        // Test revoking pending timelock
        manager.revokeVaultPendingTimelock(ITermMaxVault(address(res.vault)));
        assertEq(res.vault.timelock(), 2 days); // Original timelock

        // Test revoking pending market
        manager.revokeVaultPendingMarket(ITermMaxVault(address(res.vault)), newMarket);
        assertTrue(!res.vault.marketWhitelist(newMarket)); // Market not whitelisted

        // Test revoking pending guardian
        manager.submitVaultGuardian(ITermMaxVault(address(res.vault)), curator);
        manager.submitVaultGuardian(ITermMaxVault(address(res.vault)), newGuardian);
        manager.revokeVaultPendingGuardian(ITermMaxVault(address(res.vault)));
        assertEq(res.vault.guardian(), curator); // Original guardian

        vm.stopPrank();

        // Test without VAULT_ROLE
        address nonVaultManager = vm.randomAddress();
        vm.startPrank(nonVaultManager);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.revokeVaultPendingTimelock(ITermMaxVault(address(res.vault)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.revokeVaultPendingMarket(ITermMaxVault(address(res.vault)), newMarket);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.revokeVaultPendingGuardian(ITermMaxVault(address(res.vault)));

        vm.stopPrank();
    }

    function testUpgradeSubContract() public {
        vm.startPrank(deployer);

        // Deploy a new router implementation
        TermMaxRouterV2 routerV2 = new TermMaxRouterV2();

        // Test upgrade with DEFAULT_ADMIN_ROLE
        manager.upgradeSubContract(UUPSUpgradeable(address(res.router)), address(routerV2), "");

        // Test upgrade without DEFAULT_ADMIN_ROLE
        address nonAdmin = vm.randomAddress();
        vm.stopPrank();

        vm.startPrank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, manager.DEFAULT_ADMIN_ROLE()
            )
        );
        manager.upgradeSubContract(UUPSUpgradeable(address(res.router)), address(routerV2), "");
        vm.stopPrank();
    }

    function testSetGtImplement() public {
        address newImplement = vm.randomAddress();
        string memory gtImplementName = "TestGT";

        // Test that non-market role cannot set GT implement
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sender, manager.MARKET_ROLE()
            )
        );
        manager.setGtImplement(ITermMaxFactory(address(res.factory)), gtImplementName, newImplement);
        vm.stopPrank();

        // Test that market role can set GT implement
        vm.startPrank(deployer);
        manager.setGtImplement(ITermMaxFactory(address(res.factory)), gtImplementName, newImplement);
        assertEq(res.factory.gtImplements(keccak256(abi.encodePacked(gtImplementName))), newImplement);
        vm.stopPrank();
    }

    function testCreateMarket() public {
        bytes32 gtKey = keccak256("TestGT");
        MarketInitialParams memory params = MarketInitialParams({
            collateral: address(res.collateral),
            debtToken: IERC20Metadata(address(res.debt)),
            admin: address(manager),
            gtImplementation: address(0),
            marketConfig: marketConfig,
            loanConfig: LoanConfig({oracle: IOracle(address(0)), liquidatable: true, liquidationLtv: 0.9e8, maxLtv: 0.85e8}),
            gtInitalParams: abi.encode(1e18),
            tokenName: "Test Market",
            tokenSymbol: "Test"
        });
        uint256 salt = 123;

        // Test that non-market role cannot create market
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sender, manager.MARKET_ROLE()
            )
        );
        manager.createMarket(ITermMaxFactory(address(res.factory)), gtKey, params, salt);
        vm.stopPrank();

        // Test that market role can create market
        vm.startPrank(deployer);
        address newMarket = manager.createMarket(
            ITermMaxFactory(address(res.factory)), keccak256("GearingTokenWithERC20"), params, salt
        );
        assertTrue(newMarket != address(0));
        vm.stopPrank();
    }

    function testSubmitAndAcceptPendingOracle() public {
        address asset = address(res.collateral);
        IOracleV2.Oracle memory oracle = IOracleV2.Oracle({
            aggregator: AggregatorV3Interface(address(new MockPriceFeed(sender))),
            backupAggregator: AggregatorV3Interface(address(new MockPriceFeed(sender))),
            heartbeat: 3600,
            backupHeartbeat: 7200,
            maxPrice: 1e8,
            minPrice: 0
        });

        // Test that non-oracle role cannot submit pending oracle
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sender, manager.ORACLE_ROLE()
            )
        );
        manager.submitPendingOracle(IOracleV2(address(res.oracle)), asset, oracle);
        vm.stopPrank();

        // Test that oracle role can submit pending oracle
        vm.startPrank(deployer);
        manager.submitPendingOracle(IOracleV2(address(res.oracle)), asset, oracle);

        // Test that non-oracle role cannot accept pending oracle
        vm.stopPrank();
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sender, manager.ORACLE_ROLE()
            )
        );
        manager.acceptPendingOracle(IOracle(address(res.oracle)), asset);
        vm.stopPrank();

        // Test that oracle role can accept pending oracle
        vm.startPrank(deployer);
        manager.acceptPendingOracle(IOracle(address(res.oracle)), asset);
        vm.stopPrank();
    }

    function testRevokePendingOracle() public {
        address asset = address(res.collateral);
        IOracleV2.Oracle memory oracle = IOracleV2.Oracle({
            aggregator: AggregatorV3Interface(address(new MockPriceFeed(sender))),
            backupAggregator: AggregatorV3Interface(address(new MockPriceFeed(sender))),
            heartbeat: 3600,
            backupHeartbeat: 7200,
            maxPrice: 1e8,
            minPrice: 0
        });

        // Submit a pending oracle
        vm.startPrank(deployer);
        manager.submitPendingOracle(IOracleV2(address(res.oracle)), asset, oracle);
        vm.stopPrank();

        // Test that non-oracle role cannot revoke pending oracle
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sender, manager.ORACLE_ROLE()
            )
        );
        manager.revokePendingOracle(IOracleV2(address(res.oracle)), asset);
        vm.stopPrank();

        // Test that oracle role can revoke pending oracle
        vm.startPrank(deployer);

        // We'll capture the event to verify that revocation happened
        vm.expectEmit(true, true, true, true);
        // Define the expected event
        emit RevokePendingOracle(asset);

        // Call the revoke function
        manager.revokePendingOracle(IOracleV2(address(res.oracle)), asset);

        // Try to accept the oracle after revocation, which should fail
        // since there's no longer a pending oracle
        vm.expectRevert(); // Should revert with NoPendingValue error
        IOracle(address(res.oracle)).acceptPendingOracle(asset);

        vm.stopPrank();
    }

    // Define the event to match OracleAggregator's event
    event RevokePendingOracle(address indexed asset);

    function testUpdateGtConfig() public {
        bytes memory configData = abi.encode(1234);

        // Test that non-configurator role cannot update GT config
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sender, manager.CONFIGURATOR_ROLE()
            )
        );
        manager.updateGtConfig(ITermMaxMarket(address(res.market)), configData);
        vm.stopPrank();

        // Test that configurator role can update GT config
        vm.startPrank(deployer);
        manager.updateGtConfig(ITermMaxMarket(address(res.market)), configData);
        vm.stopPrank();
    }

    function testUpdateMarketConfig() public {
        // Get new market config from testdata
        MarketConfig memory newMarketConfig = marketConfig;
        newMarketConfig.treasurer = address(0x123);
        // Test that configurator role can update market config
        vm.prank(deployer);
        manager.updateMarketConfig(res.market, newMarketConfig);

        // Verify market config was updated
        MarketConfig memory updatedConfig = res.market.config();
        assertEq(updatedConfig.treasurer, newMarketConfig.treasurer);
    }

    function testRevokePendingMinApy() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(res.vault));
        address vaultManager = vm.randomAddress();
        uint64 newMinApy = 0.05e8; // 5% APY

        // Grant VAULT_ROLE to the vault manager
        vm.startPrank(deployer);
        manager.grantRole(manager.VAULT_ROLE(), vaultManager);
        manager.setCuratorForVault(ITermMaxVault(address(res.vault)), vaultManager);
        vm.stopPrank();

        // Setup: Submit a pending minimum APY that requires timelock
        vm.startPrank(vaultManager);
        // First set a higher APY
        vaultV2.submitPendingMinApy(0.1e8); // 10% APY (immediate)
        // Then submit a lower APY (requires timelock)
        vaultV2.submitPendingMinApy(newMinApy); // 5% APY (pending)
        vm.stopPrank();

        // Verify pending state exists
        assertEq(vaultV2.pendingMinApy().value, newMinApy);
        assertGt(vaultV2.pendingMinApy().validAt, 0);

        // Test that vault manager with VAULT_ROLE can revoke pending min APY
        vm.startPrank(vaultManager);

        // Should emit the revoke event from the vault
        vm.expectEmit(true, false, false, false);
        emit VaultEventsV2.RevokePendingMinApy(address(manager));

        manager.revokePendingMinApy(vaultV2);
        vm.stopPrank();

        // Verify pending min APY was cleared
        assertEq(vaultV2.pendingMinApy().value, 0);
        assertEq(vaultV2.pendingMinApy().validAt, 0);

        // Test without VAULT_ROLE
        address nonVaultManager = vm.randomAddress();

        // Setup another pending change to test unauthorized access
        vm.startPrank(vaultManager);
        vaultV2.submitPendingMinApy(newMinApy);
        vm.stopPrank();

        vm.startPrank(nonVaultManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.revokePendingMinApy(vaultV2);
        vm.stopPrank();

        // Verify pending state is still there after failed revoke
        assertEq(vaultV2.pendingMinApy().value, newMinApy);
        assertGt(vaultV2.pendingMinApy().validAt, 0);
    }

    function testRevokePendingPool() public {
        // Create a vault with pool functionality for testing
        VaultInitialParamsV2 memory poolParams = VaultInitialParamsV2({
            admin: address(manager),
            curator: curator,
            guardian: address(0),
            timelock: 1 days,
            asset: IERC20(address(res.debt)),
            pool: IERC4626(address(0)), // Start with no pool
            maxCapacity: 1000000e18,
            name: "Test Pool Vault",
            symbol: "tPVAULT",
            performanceFeeRate: 0.2e8,
            minApy: 0
        });

        TermMaxVaultV2 poolVault = DeployUtils.deployVault(poolParams);
        ITermMaxVaultV2 poolVaultV2 = ITermMaxVaultV2(address(poolVault));

        address vaultManager = vm.randomAddress();
        address newPoolAddress = vm.randomAddress(); // Mock pool address

        // Grant VAULT_ROLE to the vault manager
        vm.startPrank(deployer);
        manager.grantRole(manager.VAULT_ROLE(), vaultManager);
        vm.stopPrank();

        // Setup: Submit a pending pool change
        vm.startPrank(curator);
        poolVaultV2.submitPendingPool(newPoolAddress);
        vm.stopPrank();

        // Verify pending state exists
        assertEq(poolVaultV2.pendingPool().value, newPoolAddress);
        assertGt(poolVaultV2.pendingPool().validAt, 0);

        // Test that vault manager with VAULT_ROLE can revoke pending pool
        vm.startPrank(vaultManager);

        // Should emit the revoke event from the vault
        vm.expectEmit(true, false, false, false);
        emit VaultEventsV2.RevokePendingPool(address(manager));

        manager.revokePendingPool(poolVaultV2);
        vm.stopPrank();

        // Verify pending pool was cleared
        assertEq(poolVaultV2.pendingPool().value, address(0));
        assertEq(poolVaultV2.pendingPool().validAt, 0);

        // Test without VAULT_ROLE
        address nonVaultManager = vm.randomAddress();

        // Setup another pending change to test unauthorized access
        vm.startPrank(curator);
        poolVaultV2.submitPendingPool(newPoolAddress);
        vm.stopPrank();

        vm.startPrank(nonVaultManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.revokePendingPool(poolVaultV2);
        vm.stopPrank();

        // Verify pending state is still there after failed revoke
        assertEq(poolVaultV2.pendingPool().value, newPoolAddress);
        assertGt(poolVaultV2.pendingPool().validAt, 0);
    }

    function testRevokePendingMinApyWithNoExistingPending() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(res.vault));
        address vaultManager = vm.randomAddress();

        // Grant VAULT_ROLE to the vault manager
        vm.startPrank(deployer);
        manager.grantRole(manager.VAULT_ROLE(), vaultManager);
        vm.stopPrank();

        // Verify no pending min APY exists
        assertEq(vaultV2.pendingMinApy().value, 0);
        assertEq(vaultV2.pendingMinApy().validAt, 0);

        // Test revoking when there's no pending value - should not revert
        vm.startPrank(vaultManager);
        manager.revokePendingMinApy(vaultV2);
        vm.stopPrank();

        // State should remain unchanged
        assertEq(vaultV2.pendingMinApy().value, 0);
        assertEq(vaultV2.pendingMinApy().validAt, 0);
    }

    function testRevokePendingPoolWithNoExistingPending() public {
        ITermMaxVaultV2 vaultV2 = ITermMaxVaultV2(address(res.vault));
        address vaultManager = vm.randomAddress();

        // Grant VAULT_ROLE to the vault manager
        vm.startPrank(deployer);
        manager.grantRole(manager.VAULT_ROLE(), vaultManager);
        vm.stopPrank();

        // Verify no pending pool exists
        assertEq(vaultV2.pendingPool().value, address(0));
        assertEq(vaultV2.pendingPool().validAt, 0);

        // Test revoking when there's no pending value - should not revert
        vm.startPrank(vaultManager);
        manager.revokePendingPool(vaultV2);
        vm.stopPrank();

        // State should remain unchanged
        assertEq(vaultV2.pendingPool().value, address(0));
        assertEq(vaultV2.pendingPool().validAt, 0);
    }

    // Import the events for testing
    event RevokePendingMinApy(address indexed caller);
    event RevokePendingPool(address indexed caller);
}
