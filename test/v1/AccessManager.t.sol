// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {IAccessControl} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
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
import {IOwnable, IPausable, AccessManager} from "contracts/v1/access/AccessManager.sol";
import {ITermMaxRouter, TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {ITermMaxVault, TermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {Constants} from "contracts/v1/lib/Constants.sol";
import "contracts/v1/storage/TermMaxStorage.sol";

contract AccessManagerTest is Test {
    using JSONLoader for *;

    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address maker = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;
    AccessManager manager;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order =
            res.market.createOrder(maker, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts);

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

        res.router = DeployUtils.deployRouter(deployer);

        AccessManager implementation = new AccessManager();
        bytes memory data = abi.encodeCall(AccessManager.initialize, deployer);
        address proxy = address(new ERC1967Proxy(address(implementation), data));

        manager = AccessManager(proxy);

        IOwnable(address(res.factory)).transferOwnership(address(manager));
        IOwnable(address(res.market)).transferOwnership(address(manager));
        IOwnable(address(res.router)).transferOwnership(address(manager));
        IOwnable(address(res.oracle)).transferOwnership(address(manager));

        manager.acceptOwnership(IOwnable(address(res.factory)));

        manager.acceptOwnership(IOwnable(address(res.market)));

        manager.acceptOwnership(IOwnable(address(res.router)));

        manager.acceptOwnership(IOwnable(address(res.oracle)));

        manager.grantRole(manager.CONFIGURATOR_ROLE(), deployer);
        manager.grantRole(manager.PAUSER_ROLE(), deployer);
        manager.grantRole(manager.VAULT_ROLE(), deployer);
        manager.grantRole(manager.MARKET_ROLE(), deployer);
        manager.grantRole(manager.ORACLE_ROLE(), deployer);

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

    function testRenounceRole() public {
        bytes32 pauserRole = manager.PAUSER_ROLE();
        address user = vm.randomAddress();

        // Grant role first
        vm.prank(deployer);
        manager.grantRole(pauserRole, user);

        // Renounce role
        vm.prank(user);
        manager.renounceRole(pauserRole, user);

        assertFalse(manager.hasRole(pauserRole, user));
    }

    function testCannotRenounceDefaultAdminRole() public {
        bytes32 defaultAdminRole = 0x00;

        vm.prank(deployer);
        vm.expectRevert(AccessManager.CannotRevokeDefaultAdminRole.selector);
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

    function testVaultManagement() public {
        address vaultManager = vm.randomAddress();
        address newCurator = vm.randomAddress();

        // Create vault initialization parameters
        VaultInitialParams memory params = VaultInitialParams({
            admin: address(manager),
            curator: address(0), // Will be set through AccessManager
            timelock: 1 days,
            asset: IERC20(address(res.debt)),
            maxCapacity: 1000000e18,
            name: "Test Vault",
            symbol: "tVAULT",
            performanceFeeRate: 0.2e8 // 20%
        });

        // Deploy vault
        ITermMaxVault vault = DeployUtils.deployVault(params);

        // Grant VAULT_ROLE to the vault manager
        vm.startPrank(deployer);
        manager.grantRole(manager.VAULT_ROLE(), vaultManager);
        vm.stopPrank();

        vm.startPrank(vaultManager);

        // Test setting curator
        manager.setCuratorForVault(ITermMaxVault(address(vault)), newCurator);
        assertEq(ITermMaxVault(address(vault)).curator(), newCurator);

        vm.stopPrank();

        // Test without VAULT_ROLE
        address nonVaultManager = vm.randomAddress();
        vm.startPrank(nonVaultManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.setCuratorForVault(ITermMaxVault(address(vault)), newCurator);
        vm.stopPrank();

        // Test that non-vault role cannot set allocator
        address allocator = vm.randomAddress();
        vm.startPrank(allocator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, allocator, manager.VAULT_ROLE()
            )
        );
        manager.setIsAllocatorForVault(ITermMaxVault(address(vault)), allocator, true);
        vm.stopPrank();

        // Test that vault role can set allocator
        vm.prank(deployer);
        manager.setIsAllocatorForVault(ITermMaxVault(address(vault)), allocator, true);
        assertTrue(vault.isAllocator(allocator));
    }

    function testRevokeVaultPendingValues() public {
        address vaultManager = vm.randomAddress();
        address newMarket = vm.randomAddress();
        address newGuardian = vm.randomAddress();
        address curator = vm.randomAddress();

        // Create vault initialization parameters
        VaultInitialParams memory params = VaultInitialParams({
            admin: address(manager),
            curator: curator,
            timelock: 1 days,
            asset: IERC20(address(res.debt)),
            maxCapacity: 1000000e18,
            name: "Test Vault",
            symbol: "tVAULT",
            performanceFeeRate: 0.2e8
        });

        // Deploy vault
        ITermMaxVault vault = DeployUtils.deployVault(params);

        // Grant VAULT_ROLE to the vault manager and set curator
        vm.startPrank(deployer);
        manager.grantRole(manager.VAULT_ROLE(), vaultManager);
        vm.stopPrank();

        vm.startPrank(curator);
        vault.submitTimelock(2 days);
        vault.submitTimelock(1 days);
        vault.submitMarket(newMarket, true);
        vm.stopPrank();

        vm.startPrank(vaultManager);
        manager.setCuratorForVault(ITermMaxVault(address(vault)), vaultManager);

        // Test revoking pending timelock
        manager.revokeVaultPendingTimelock(ITermMaxVault(address(vault)));
        assertEq(vault.timelock(), 2 days); // Original timelock

        // Test revoking pending market
        manager.revokeVaultPendingMarket(ITermMaxVault(address(vault)), newMarket);
        assertTrue(!vault.marketWhitelist(newMarket)); // Market not whitelisted

        // Test revoking pending guardian
        manager.submitVaultGuardian(vault, curator);
        manager.submitVaultGuardian(vault, newGuardian);
        manager.revokeVaultPendingGuardian(ITermMaxVault(address(vault)));
        assertEq(vault.guardian(), curator); // Original guardian

        vm.stopPrank();

        // Test without VAULT_ROLE
        address nonVaultManager = vm.randomAddress();
        vm.startPrank(nonVaultManager);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.revokeVaultPendingTimelock(ITermMaxVault(address(vault)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.revokeVaultPendingMarket(ITermMaxVault(address(vault)), newMarket);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonVaultManager, manager.VAULT_ROLE()
            )
        );
        manager.revokeVaultPendingGuardian(ITermMaxVault(address(vault)));

        vm.stopPrank();
    }

    function testUpgradeSubContract() public {
        vm.startPrank(deployer);

        // Deploy a new router implementation
        TermMaxRouter routerV2 = new TermMaxRouter();

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

    function testSetAdapterWhitelist() public {
        address adapter = vm.randomAddress();

        // Test that non-market role cannot set adapter whitelist
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sender, manager.MARKET_ROLE()
            )
        );
        manager.setAdapterWhitelist(ITermMaxRouter(address(res.router)), adapter, true);
        vm.stopPrank();

        // Test that market role can set adapter whitelist
        vm.startPrank(deployer);
        manager.setAdapterWhitelist(ITermMaxRouter(address(res.router)), adapter, true);
        assertTrue(res.router.adapterWhitelist(adapter));

        // Test setting adapter whitelist to false
        manager.setAdapterWhitelist(ITermMaxRouter(address(res.router)), adapter, false);
        assertFalse(res.router.adapterWhitelist(adapter));
        vm.stopPrank();
    }

    function testSubmitAndAcceptPendingOracle() public {
        address asset = address(res.collateral);
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: AggregatorV3Interface(address(new MockPriceFeed(sender))),
            backupAggregator: AggregatorV3Interface(address(new MockPriceFeed(sender))),
            heartbeat: 3600
        });

        // Test that non-oracle role cannot submit pending oracle
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sender, manager.ORACLE_ROLE()
            )
        );
        manager.submitPendingOracle(IOracle(address(res.oracle)), asset, oracle);
        vm.stopPrank();

        // Test that oracle role can submit pending oracle
        vm.startPrank(deployer);
        manager.submitPendingOracle(IOracle(address(res.oracle)), asset, oracle);

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

    function testUpdateOrderFeeRate() public {
        // Get new fee config from testdata
        FeeConfig memory newFeeConfig = res.order.orderConfig().feeConfig;

        // Test that non-admin cannot update fee rate
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sender, manager.CONFIGURATOR_ROLE()
            )
        );
        manager.updateOrderFeeRate(res.market, res.order, newFeeConfig);
        vm.stopPrank();
        // Test that admin can update fee rate
        vm.prank(deployer);
        manager.updateOrderFeeRate(res.market, res.order, newFeeConfig);

        // Verify fee config was updated
        OrderConfig memory updatedConfig = res.order.orderConfig();
        assertEq(updatedConfig.feeConfig.lendTakerFeeRatio, newFeeConfig.lendTakerFeeRatio);
        assertEq(updatedConfig.feeConfig.borrowTakerFeeRatio, newFeeConfig.borrowTakerFeeRatio);
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
}
