// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";

import {IAccessControl} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, Pausable} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface, GearingTokenWithERC20} from "../contracts/core/factory/TermMaxFactory.sol";
import "../contracts/core/storage/TermMaxStorage.sol";
import {IOwnable, AccessManager} from "contracts/access/AccessManager.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";

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

        manager = new AccessManager(deployer);

        IOwnable(address(res.factory)).transferOwnership(address(manager));
        IOwnable(address(res.market)).transferOwnership(address(manager));
        IOwnable(address(router)).transferOwnership(address(manager));

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

        MockPriceFeed underlyingOracle = new MockPriceFeed(deployer);
        MockPriceFeed collateralOracle = new MockPriceFeed(deployer);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                underlyingOracle: underlyingOracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(collateralOracle)
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

        MockPriceFeed underlyingOracle = new MockPriceFeed(deployer);
        MockPriceFeed collateralOracle = new MockPriceFeed(deployer);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                underlyingOracle: underlyingOracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(collateralOracle)
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

        MockPriceFeed underlyingOracle = new MockPriceFeed(deployer);
        MockPriceFeed collateralOracle = new MockPriceFeed(deployer);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                underlyingOracle: underlyingOracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(collateralOracle)
            });
        vm.warp(marketConfig.openTime - 1 days);
        IOwnable(address(factory)).transferOwnership(address(manager));
        address market = manager.createMarketAndWhitelist(router, factory, params);
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

    function testSetTreasurer() public {
        vm.startPrank(deployer);
        address newTreasurer = vm.randomAddress();

        vm.expectEmit();
        emit ITermMaxMarket.UpdateTreasurer(newTreasurer);

        manager.setMarketTreasurer(res.market, newTreasurer);
        assert(res.market.config().treasurer == newTreasurer);

        assert(res.gt.getGtConfig().treasurer == newTreasurer);
        vm.stopPrank();
    }

    function testSetTreasurerWithoutAuth() public {
        vm.startPrank(sender);
        address newTreasurer = vm.randomAddress();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.CURATOR_ROLE()
            )
        );
        manager.setMarketTreasurer(res.market, newTreasurer);

        vm.stopPrank();
    }

    function testSetFee() public {
        vm.startPrank(deployer);

        uint32 lendFeeRatio = 0.01e8;
        uint32 minNLendFeeR = 0.02e8;
        uint32 borrowFeeRatio = 0.03e8;
        uint32 minNBorrowFeeR = 0.04e8;
        uint32 redeemFeeRatio = 0.05e8;
        uint32 issueFtFeeRatio = 0.06e8;
        uint32 lockingPercentage = 0.07e8;
        uint32 protocolFeeRatio = 0.08e8;
        vm.expectEmit();
        emit ITermMaxMarket.UpdateFeeRate(
            lendFeeRatio,
            minNLendFeeR,
            borrowFeeRatio,
            minNBorrowFeeR,
            redeemFeeRatio,
            issueFtFeeRatio,
            lockingPercentage,
            protocolFeeRatio
        );
        manager.setMarketFeeRate(
            res.market,
            lendFeeRatio,
            minNLendFeeR,
            borrowFeeRatio,
            minNBorrowFeeR,
            redeemFeeRatio,
            issueFtFeeRatio,
            lockingPercentage,
            protocolFeeRatio
        );

        assert(res.market.config().lendFeeRatio == lendFeeRatio);
        assert(res.market.config().minNLendFeeR == minNLendFeeR);
        assert(res.market.config().borrowFeeRatio == borrowFeeRatio);
        assert(res.market.config().minNBorrowFeeR == minNBorrowFeeR);
        assert(res.market.config().redeemFeeRatio == redeemFeeRatio);
        assert(res.market.config().issueFtFeeRatio == issueFtFeeRatio);
        assert(res.market.config().lockingPercentage == lockingPercentage);
        assert(res.market.config().protocolFeeRatio == protocolFeeRatio);
        vm.stopPrank();
    }

    function testSetFeeWithoutAuth() public {
        vm.startPrank(sender);

        uint32 lendFeeRatio = 0.01e8;
        uint32 minNLendFeeR = 0.02e8;
        uint32 borrowFeeRatio = 0.03e8;
        uint32 minNBorrowFeeR = 0.04e8;
        uint32 redeemFeeRatio = 0.05e8;
        uint32 issueFtFeeRatio = 0.06e8;
        uint32 lockingPercentage = 0.07e8;
        uint32 protocolFeeRatio = 0.08e8;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.CURATOR_ROLE()
            )
        );
        manager.setMarketFeeRate(
            res.market,
            lendFeeRatio,
            minNLendFeeR,
            borrowFeeRatio,
            minNBorrowFeeR,
            redeemFeeRatio,
            issueFtFeeRatio,
            lockingPercentage,
            protocolFeeRatio
        );
        vm.stopPrank();
    }

    function testSetLsf() public {
        vm.startPrank(deployer);
        uint32 lsf = 0.11e8;

        vm.expectEmit();
        emit ITermMaxMarket.UpdateLsf(lsf);
        manager.setMarketLsf(res.market, lsf);

        assert(res.market.config().lsf == lsf);

        vm.stopPrank();
    }

    function testSetLsfWithoutAuth() public {
        vm.startPrank(sender);
        uint32 lsf = 0.11e8;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.CURATOR_ROLE()
            )
        );
        manager.setMarketLsf(res.market, lsf);

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
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.CURATOR_ROLE()
            )
        );
        manager.setProviderWhitelist(res.market, sender, true);

        vm.stopPrank();
    }

    function testSetSwitchOfMintingGt() public {
        vm.prank(deployer);
        vm.expectEmit();
        emit IGearingToken.UpdateMintingSwitch(false);
        manager.setSwitchOfMintingGt(res.market, false);
    }

    function testSetSwitchOfMintingGtWithoutAuth() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.CURATOR_ROLE()
            )
        );
        vm.prank(sender);
        manager.setSwitchOfMintingGt(res.market, false);
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

    function testSetSwitchOfGt() public {
        vm.startPrank(deployer);
        manager.setSwitchOfGt(res.market, false);
        assert(Pausable(address(res.gt)).paused() == true);
        manager.setSwitchOfGt(res.market, true);
        assert(Pausable(address(res.gt)).paused() == false);
        vm.stopPrank();
    }

    function testSetSwitchOfGtWithoutAut() public {
        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                sender,
                manager.PAUSER_ROLE()
            )
        );
        manager.setSwitchOfGt(res.market, false);
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

    function testSetSwitchOfRouterWithoutAut() public {
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
}
