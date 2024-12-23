// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";

import {IAccessControl} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, Pausable} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, GearingTokenWithERC20} from "../contracts/core/factory/TermMaxFactory.sol";
import "../contracts/core/storage/TermMaxStorage.sol";
import {IOwnable, AccessManager} from "contracts/access/AccessManager.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";

contract AccessManagerTest is Test {
    address deployer = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;
    MarketConfig marketConfig;
    DeployUtils.Res res;

    AccessManager manager;
    TermMaxRouter router;

    function setUp() public {
        string memory testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/testdata.json")
        );

        vm.startPrank(deployer);
        testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/testdata.json")
        );

        marketConfig = JSONLoader.getMarketConfigFromJson(
            treasurer,
            testdata,
            ".marketConfig"
        );
        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );

        vm.warp(
            vm.parseUint(
                vm.parseJsonString(testdata, ".marketConfig.currentTime")
            )
        );

        router = DeployUtils.deployRouter(deployer);

        AccessManager implementation = new AccessManager();
        bytes memory data = abi.encodeCall(AccessManager.initialize, deployer);
        address proxy = address(
            new ERC1967Proxy(address(implementation), data)
        );

        manager = AccessManager(proxy);

        IOwnable(address(res.factory)).transferOwnership(address(manager));
        IOwnable(address(res.market)).transferOwnership(address(manager));
        IOwnable(address(router)).transferOwnership(address(manager));
        IOwnable(address(res.oracle)).transferOwnership(address(manager));

        uint amount = 10000e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(uint128(amount));

        manager.grantRole(manager.CURATOR_ROLE(), deployer);
        manager.grantRole(manager.PAUSER_ROLE(), deployer);

        vm.stopPrank();

        res.underlying.mint(sender, amount);

        vm.startPrank(sender);
        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(uint128(amount));
        vm.stopPrank();
    }

    function testTransferOwnership() public {
        vm.prank(deployer);
        manager.transferOwnership(address(router), sender);

        assert(router.owner() == sender);
    }

    function testTransferOwnershipWithoutAuth() public {
        vm.prank(sender);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                uint(0)
            )
        );
        manager.transferOwnership(address(router), sender);
    }

    function testCreateMarket() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();

        vm.expectEmit();
        emit ITermMaxFactory.InitializeMarketImplement(address(m));
        factory.initMarketImplement(address(m));

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 underlying = new MockERC20("DAI", "DAI", 8);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                oracle: res.oracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(0)
            });
        vm.warp(marketConfig.openTime - 1 days);
        IOwnable(address(factory)).transferOwnership(address(manager));
        manager.createMarket(factory, params);
        vm.stopPrank();
    }

    function testCreateMarketWithoutAuth() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();

        vm.expectEmit();
        emit ITermMaxFactory.InitializeMarketImplement(address(m));
        factory.initMarketImplement(address(m));

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 underlying = new MockERC20("DAI", "DAI", 8);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                oracle: res.oracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(0)
            });
        vm.warp(marketConfig.openTime - 1 days);
        IOwnable(address(factory)).transferOwnership(address(manager));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                uint(0)
            )
        );
        vm.prank(sender);
        manager.createMarket(factory, params);
    }

    function testCreateMarketAndWhitelist() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();

        vm.expectEmit();
        emit ITermMaxFactory.InitializeMarketImplement(address(m));
        factory.initMarketImplement(address(m));

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 underlying = new MockERC20("DAI", "DAI", 8);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                oracle: res.oracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(0)
            });
        vm.warp(marketConfig.openTime - 1 days);
        IOwnable(address(factory)).transferOwnership(address(manager));
        address market = manager.createMarketAndWhitelist(
            router,
            factory,
            params
        );
        assert(router.marketWhitelist(market));
        vm.stopPrank();
    }

    function testUpgradeSubContract() public {
        TermMaxRouter routerV2 = new TermMaxRouter();

        vm.startPrank(deployer);
        vm.expectEmit();
        emit IERC1967.Upgraded(address(routerV2));
        manager.upgradeSubContract(router, address(routerV2), "");

        vm.stopPrank();
    }

    function testUpgradeSubContractWithoutAuth() public {
        TermMaxRouter routerV2 = new TermMaxRouter();

        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                uint(0)
            )
        );
        manager.upgradeSubContract(router, address(routerV2), "");

        vm.stopPrank();
    }

    function testSetGtImplement() public {
        vm.startPrank(deployer);
        address gt = vm.randomAddress();

        string memory gtImplemtName = "gt-test";
        bytes32 key = keccak256(abi.encodePacked(gtImplemtName));
        vm.expectEmit();
        emit ITermMaxFactory.SetGtImplement(key, gt);
        manager.setGtImplement(res.factory, gtImplemtName, gt);
        assert(res.factory.gtImplements(key) == address(gt));
        vm.stopPrank();
    }

    function testSetGtImplementWithoutAuth() public {
        vm.startPrank(sender);
        address gt = vm.randomAddress();
        string memory gtImplemtName = "gt-test";
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                uint(0)
            )
        );
        manager.setGtImplement(res.factory, gtImplemtName, gt);
        vm.stopPrank();
    }

    function testUpdateMarketConfig() public {
        vm.startPrank(deployer);

        MarketConfig memory newConfig = res.market.config();
        newConfig.treasurer = vm.randomAddress();
        newConfig.lsf = 0.11e8;
        newConfig.lendFeeRatio = 0.01e8;
        newConfig.minNLendFeeR = 0.02e8;
        newConfig.borrowFeeRatio = 0.03e8;
        newConfig.minNBorrowFeeR = 0.04e8;
        newConfig.redeemFeeRatio = 0.05e8;
        newConfig.issueFtFeeRatio = 0.06e8;
        newConfig.lockingPercentage = 0.07e8;
        newConfig.protocolFeeRatio = 0.08e8;

        vm.expectEmit();
        emit ITermMaxMarket.UpdateMarketConfig(newConfig);
        manager.updateMarketConfig(res.market, newConfig);

        MarketConfig memory updatedConfig = res.market.config();
        assertEq(updatedConfig.treasurer, newConfig.treasurer);
        assertEq(updatedConfig.lsf, newConfig.lsf);
        assertEq(updatedConfig.lendFeeRatio, newConfig.lendFeeRatio);
        assertEq(updatedConfig.minNLendFeeR, newConfig.minNLendFeeR);
        assertEq(updatedConfig.borrowFeeRatio, newConfig.borrowFeeRatio);
        assertEq(updatedConfig.minNBorrowFeeR, newConfig.minNBorrowFeeR);
        assertEq(updatedConfig.redeemFeeRatio, newConfig.redeemFeeRatio);
        assertEq(updatedConfig.issueFtFeeRatio, newConfig.issueFtFeeRatio);
        assertEq(updatedConfig.lockingPercentage, newConfig.lockingPercentage);
        assertEq(updatedConfig.protocolFeeRatio, newConfig.protocolFeeRatio);

        vm.stopPrank();
    }

    function testUpdateMarketConfigWithoutAuth() public {
        vm.startPrank(sender);

        MarketConfig memory newConfig = res.market.config();
        newConfig.treasurer = vm.randomAddress();
        newConfig.lsf = 0.11e8;
        newConfig.lendFeeRatio = 0.01e8;
        newConfig.minNLendFeeR = 0.02e8;
        newConfig.borrowFeeRatio = 0.03e8;
        newConfig.minNBorrowFeeR = 0.04e8;
        newConfig.redeemFeeRatio = 0.05e8;
        newConfig.issueFtFeeRatio = 0.06e8;
        newConfig.lockingPercentage = 0.07e8;
        newConfig.protocolFeeRatio = 0.08e8;

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessManager.MsgSenderIsNotCurator.selector,
                res.market
            )
        );
        manager.updateMarketConfig(res.market, newConfig);
        vm.stopPrank();
    }

    function testUpdateMarketConfigInvalidLsf() public {
        vm.startPrank(deployer);

        MarketConfig memory newConfig = res.market.config();
        newConfig.lsf = uint32(Constants.DECIMAL_BASE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.InvalidLsf.selector,
                newConfig.lsf
            )
        );
        manager.updateMarketConfig(res.market, newConfig);

        newConfig.lsf = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.InvalidLsf.selector,
                newConfig.lsf
            )
        );
        manager.updateMarketConfig(res.market, newConfig);

        vm.stopPrank();
    }

    function testSetGtCapacity() public {
        vm.startPrank(deployer);
        uint256 newGtCapacity = 1000e8;
        vm.expectEmit();
        emit IGearingToken.UpdateConfig(abi.encode(newGtCapacity));
        manager.updateGtConfig(res.market, abi.encode(newGtCapacity));
        assert(
            GearingTokenWithERC20(address(res.gt)).collateralCapacity() ==
                newGtCapacity
        );
        vm.stopPrank();
    }

    function testSetGtCapacityWithoutAuth() public {
        vm.startPrank(sender);
        uint256 newGtCapacity = 1000e8;
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessManager.MsgSenderIsNotCurator.selector,
                res.market
            )
        );
        manager.updateGtConfig(res.market, abi.encode(newGtCapacity));
        vm.stopPrank();
    }

    function testSetOracle() public {
        vm.startPrank(deployer);

        MockPriceFeed pricefeed = new MockPriceFeed(deployer);
        IOracle.Oracle memory oracle = IOracle.Oracle(pricefeed, pricefeed, 1);

        vm.expectEmit();
        emit IOracle.UpdateOracle(
            address(res.collateral),
            pricefeed,
            pricefeed,
            1
        );
        manager.setOracle(res.oracle, address(res.collateral), oracle);

        (
            AggregatorV3Interface aggregator,
            AggregatorV3Interface backupAggregator,
            uint32 heartbeat
        ) = OracleAggregator(address(res.oracle)).oracles(
                address(res.collateral)
            ); // onChain
        assert(aggregator == oracle.aggregator);
        assert(backupAggregator == oracle.backupAggregator);
        assert(heartbeat == oracle.heartbeat);
        vm.stopPrank();
    }

    function testSetOracleWithoutAuth() public {
        vm.startPrank(sender);

        MockPriceFeed pricefeed = new MockPriceFeed(deployer);
        IOracle.Oracle memory oracle = IOracle.Oracle(pricefeed, pricefeed, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.DEFAULT_ADMIN_ROLE()
            )
        );
        manager.setOracle(res.oracle, address(res.collateral), oracle);
        vm.stopPrank();
    }

    function testRemoveOracle() public {
        vm.startPrank(deployer);

        address asset = vm.randomAddress();
        AggregatorV3Interface aggregator = AggregatorV3Interface(
            vm.randomAddress()
        );
        AggregatorV3Interface backupAggregator = AggregatorV3Interface(
            vm.randomAddress()
        );
        uint32 heartbeat = 3600;

        // First set an oracle
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: aggregator,
            backupAggregator: backupAggregator,
            heartbeat: heartbeat
        });
        manager.setOracle(res.oracle, asset, oracle);

        // Then remove it
        vm.expectEmit();
        emit IOracle.UpdateOracle(
            asset,
            AggregatorV3Interface(address(0)),
            AggregatorV3Interface(address(0)),
            0
        );
        manager.removeOracle(res.oracle, asset);

        vm.stopPrank();
    }

    function testRemoveOracleWithoutAuth() public {
        vm.startPrank(sender);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.DEFAULT_ADMIN_ROLE()
            )
        );
        manager.removeOracle(res.oracle, address(0));

        vm.stopPrank();
    }

    function testRemoveOracleInvalidAsset() public {
        vm.startPrank(deployer);

        vm.expectRevert(IOracle.InvalidAssetOrOracle.selector);
        manager.removeOracle(res.oracle, address(0));

        vm.stopPrank();
    }

    function testSetOracleInvalidAsset() public {
        vm.startPrank(deployer);

        // Test with zero asset address
        AggregatorV3Interface aggregator = AggregatorV3Interface(
            vm.randomAddress()
        );
        AggregatorV3Interface backupAggregator = AggregatorV3Interface(
            vm.randomAddress()
        );
        uint32 heartbeat = 3600;

        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: aggregator,
            backupAggregator: backupAggregator,
            heartbeat: heartbeat
        });

        vm.expectRevert(IOracle.InvalidAssetOrOracle.selector);
        manager.setOracle(res.oracle, address(0), oracle);

        // Test with zero aggregator address
        oracle.aggregator = AggregatorV3Interface(address(0));
        oracle.backupAggregator = backupAggregator;

        vm.expectRevert(IOracle.InvalidAssetOrOracle.selector);
        manager.setOracle(res.oracle, vm.randomAddress(), oracle);

        // Test with zero backup aggregator address
        oracle.aggregator = aggregator;
        oracle.backupAggregator = AggregatorV3Interface(address(0));

        vm.expectRevert(IOracle.InvalidAssetOrOracle.selector);
        manager.setOracle(res.oracle, vm.randomAddress(), oracle);

        vm.stopPrank();
    }

    function testSetProviderWhitelist() public {
        vm.startPrank(deployer);

        vm.expectEmit();
        emit ITermMaxMarket.UpdateProviderWhitelist(sender, true);
        manager.setProviderWhitelist(res.market, sender, true);

        vm.stopPrank();
    }

    function testSetProviderWhitelistWithoutAuth() public {
        vm.startPrank(sender);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessManager.MsgSenderIsNotCurator.selector,
                res.market
            )
        );
        manager.setProviderWhitelist(res.market, sender, true);

        vm.stopPrank();
    }

    function testSetMarketWhitelist() public {
        vm.prank(deployer);
        manager.setMarketWhitelist(router, address(res.market), false);
        assert(router.marketWhitelist(address(res.market)) == false);
    }

    function testSetMarketWhitelistWithoutAuth() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(sender);
        manager.setMarketWhitelist(router, address(res.market), false);
    }

    function testSetAdapterWhitelist() public {
        address adapter = vm.randomAddress();
        vm.prank(deployer);
        manager.setAdapterWhitelist(router, adapter, true);
        assert(router.adapterWhitelist(adapter) == true);
    }

    function testSetAdapterWhitelistWithoutAuth() public {
        address adapter = vm.randomAddress();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(sender);
        manager.setAdapterWhitelist(router, adapter, true);
    }

    function testSetSwitchOfMarket() public {
        vm.startPrank(deployer);
        manager.setSwitchOfMarket(res.market, false);
        assert(Pausable(address(res.market)).paused() == true);
        manager.setSwitchOfMarket(res.market, true);
        assert(Pausable(address(res.market)).paused() == false);
        vm.stopPrank();
    }

    function testSetSwitchOfMarketWithoutAuth() public {
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.PAUSER_ROLE()
            )
        );
        manager.setSwitchOfMarket(res.market, false);
        vm.stopPrank();
    }

    function testSetSwitchOfRouter() public {
        vm.startPrank(deployer);
        manager.setSwitchOfRouter(router, false);
        assert(router.paused() == false);
        manager.setSwitchOfRouter(router, true);
        assert(router.paused() == true);
        vm.stopPrank();
    }

    function testSetSwitchOfRouterWithoutAuth() public {
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.PAUSER_ROLE()
            )
        );
        manager.setSwitchOfRouter(router, false);
        vm.stopPrank();
    }

    function testWithdrawExcessFtXt() public {
        vm.startPrank(deployer);
        res.lpFt.approve(address(res.market), res.lpFt.balanceOf(deployer));
        res.lpXt.approve(address(res.market), res.lpXt.balanceOf(deployer));
        (uint128 excessFt, uint128 excessXt) = res.market.withdrawLiquidity(
            uint128(res.lpFt.balanceOf(deployer) / 2),
            uint128(res.lpXt.balanceOf(deployer) / 2)
        );
        res.ft.transfer(address(res.market), excessFt);
        res.xt.transfer(address(res.market), excessXt);

        address recipient = vm.randomAddress();

        // Record initial balances
        uint256 initialRecipientFt = res.ft.balanceOf(recipient);
        uint256 initialRecipientXt = res.xt.balanceOf(recipient);

        // Get initial reserves
        (uint256 ftReserve, uint256 xtReserve) = res.market.ftXtReserves();

        // Withdraw excess tokens through AccessManager
        vm.expectEmit();
        emit ITermMaxMarket.WithdrawExcessFtXt(recipient, excessFt, excessXt);
        manager.withdrawExcessFtXt(res.market, recipient, excessFt, excessXt);

        // Verify balances
        assertEq(
            res.ft.balanceOf(recipient),
            initialRecipientFt + excessFt,
            "Incorrect FT balance after withdrawal"
        );
        assertEq(
            res.xt.balanceOf(recipient),
            initialRecipientXt + excessXt,
            "Incorrect XT balance after withdrawal"
        );

        // Verify reserves unchanged
        (uint256 newFtReserve, uint256 newXtReserve) = res
            .market
            .ftXtReserves();
        assertEq(newFtReserve, ftReserve, "FT reserve should not change");
        assertEq(newXtReserve, xtReserve, "XT reserve should not change");

        vm.stopPrank();
    }

    function testWithdrawExcessFtXtWhenPaused() public {
        vm.startPrank(deployer);

        // First pause the market
        manager.setSwitchOfMarket(res.market, false);

        uint128 ftAmt = 1e18;
        uint128 xtAmt = 1e18;

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        manager.withdrawExcessFtXt(res.market, deployer, ftAmt, xtAmt);

        vm.stopPrank();
    }

    function testWithdrawExcessFtXtAfterMaturity() public {
        vm.startPrank(deployer);

        // Set time after market maturity
        vm.warp(marketConfig.maturity + 1);

        uint128 ftAmt = 1e18;
        uint128 xtAmt = 1e18;

        vm.expectRevert(ITermMaxMarket.MarketIsNotOpen.selector);
        manager.withdrawExcessFtXt(res.market, deployer, ftAmt, xtAmt);

        vm.stopPrank();
    }

    function testWithdrawExcessFtXtWithoutAuth() public {
        vm.startPrank(sender);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.DEFAULT_ADMIN_ROLE()
            )
        );
        manager.withdrawExcessFtXt(res.market, sender, 1, 1);

        vm.stopPrank();
    }

    function testMarketCurator() public {
        address curator = vm.randomAddress();

        // Test setting curator
        vm.prank(deployer);
        manager.setMarketCurator(res.market, curator);
        assertEq(manager.marketCurators(res.market), curator);

        // Test curator permissions
        vm.startPrank(curator);
        MarketConfig memory newConfig = res.market.config();
        manager.updateMarketConfig(res.market, newConfig);
        manager.setProviderWhitelist(res.market, vm.randomAddress(), true);
        manager.updateGtConfig(res.market, abi.encode(1));
        vm.stopPrank();

        // Test non-curator permissions
        vm.prank(vm.randomAddress());
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessManager.MsgSenderIsNotCurator.selector,
                res.market
            )
        );
        manager.updateMarketConfig(res.market, newConfig);
    }

    function testSetMarketCuratorByNonAdmin() public {
        address curator = vm.randomAddress();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(sender);
        manager.setMarketCurator(res.market, curator);
    }

    function testMarketCuratorAndGlobalCurator() public {
        address marketCurator = vm.randomAddress();
        address globalCurator = vm.randomAddress();

        vm.startPrank(deployer);
        manager.setMarketCurator(res.market, marketCurator);
        manager.grantRole(manager.CURATOR_ROLE(), globalCurator);
        vm.stopPrank();

        // Test market curator permissions
        vm.startPrank(marketCurator);
        MarketConfig memory newConfig = res.market.config();
        manager.updateMarketConfig(res.market, newConfig);
        vm.stopPrank();

        // Test global curator permissions
        vm.startPrank(globalCurator);
        manager.updateMarketConfig(res.market, newConfig);
        vm.stopPrank();
    }

    function testCannotRevokeDefaultAdminRole() public {
        bytes32 defaultAdminRole = 0x00;

        vm.prank(deployer);
        vm.expectRevert(AccessManager.CannotRevokeDefaultAdminRole.selector);
        manager.revokeRole(defaultAdminRole, deployer);
    }
}
