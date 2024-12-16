// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, GearingTokenWithERC20} from "../contracts/core/factory/TermMaxFactory.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import "../contracts/core/storage/TermMaxStorage.sol";

contract FactoryTest is Test {
    address deployer = vm.randomAddress();

    address treasurer = vm.randomAddress();
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;
    MarketConfig marketConfig;

    function setUp() public {
        string memory testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/testdata.json")
        );

        marketConfig = JSONLoader.getMarketConfigFromJson(
            treasurer,
            testdata,
            ".marketConfig"
        );
        marketConfig.rewardIsDistributed = false;

        vm.warp(marketConfig.openTime - 1 days);
    }

    function testDeploy() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();

        vm.expectEmit();
        emit ITermMaxFactory.InitializeMarketImplement(address(m));
        factory.initMarketImplement(address(m));

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 underlying = new MockERC20("DAI", "DAI", 8);

        IOracle oracle = IOracle(vm.randomAddress());
        uint collateralCapacity = type(uint256).max;
        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                oracle: oracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(collateralCapacity)
            });

        vm.expectEmit();

        ITermMaxMarket market = ITermMaxMarket(factory.createMarket(params));
        assert(
            keccak256(abi.encode(market.config())) ==
                keccak256(abi.encode(marketConfig))
        );
        (IMintableERC20 ft, , , , IGearingToken gt, , ) = market.tokens();
        IGearingToken.GtConfig memory gtConfig = IGearingToken.GtConfig({
            market: address(market),
            collateral: address(collateral),
            underlying: underlying,
            ft: ft,
            treasurer: treasurer,
            oracle: oracle,
            maturity: marketConfig.maturity,
            liquidationLtv: liquidationLtv,
            maxLtv: maxLtv,
            liquidatable: true
        });
        assert(
            keccak256(abi.encode(gt.getGtConfig())) ==
                keccak256(abi.encode(gtConfig))
        );
        assert(GearingTokenWithERC20(address(gt)).collateralCapacity() == collateralCapacity);
        vm.stopPrank();
    }

    function testDeployRepeatedly() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();

        vm.expectEmit();
        emit ITermMaxFactory.InitializeMarketImplement(address(m));
        factory.initMarketImplement(address(m));

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 underlying = new MockERC20("DAI", "DAI", 8);

        IOracle oracle = IOracle(vm.randomAddress());
        uint collateralCapacity = type(uint256).max;
        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                oracle: oracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(collateralCapacity)
            });

        vm.expectEmit();
        
        ITermMaxMarket market = ITermMaxMarket(factory.createMarket(params));
        assert(
            keccak256(abi.encode(market.config())) ==
                keccak256(abi.encode(marketConfig))
        );
        (IMintableERC20 ft, , , , IGearingToken gt, , ) = market.tokens();
        IGearingToken.GtConfig memory gtConfig = IGearingToken.GtConfig({
            market: address(market),
            collateral: address(collateral),
            underlying: underlying,
            ft: ft,
            treasurer: treasurer,
            oracle: oracle,
            maturity: marketConfig.maturity,
            liquidationLtv: liquidationLtv,
            maxLtv: maxLtv,
            liquidatable: true
        });
        assert(
            keccak256(abi.encode(gt.getGtConfig())) ==
                keccak256(abi.encode(gtConfig))
        );
        assert(GearingTokenWithERC20(address(gt)).collateralCapacity() == collateralCapacity);

        vm.expectRevert(abi.encodeWithSignature("FailedDeployment()"));
        factory.createMarket(params);

        vm.stopPrank();
    }

    function testDeployMarketWithInvalidTime() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();
        factory.initMarketImplement(address(m));

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 underlying = new MockERC20("DAI", "DAI", 8);

        marketConfig.openTime = uint64(block.timestamp - 1);
        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                oracle: IOracle(vm.randomAddress()),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(0)
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.InvalidTime.selector,
                marketConfig.openTime,
                marketConfig.maturity
            )
        );
        factory.createMarket(params);

        params.marketConfig.openTime = uint64(block.timestamp + 3600);
        params.marketConfig.maturity = uint64(block.timestamp + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.InvalidTime.selector,
                params.marketConfig.openTime,
                params.marketConfig.maturity
            )
        );
        factory.createMarket(params);

        vm.stopPrank();
    }

    function testDeployMarketWithInvalidLsf() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();
        factory.initMarketImplement(address(m));

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 underlying = new MockERC20("DAI", "DAI", 8);

        marketConfig.lsf = 0;
        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                oracle: IOracle(vm.randomAddress()),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(0)
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.InvalidLsf.selector,
                marketConfig.lsf
            )
        );
        factory.createMarket(params);

        vm.stopPrank();
    }

    function testRevertByMarketImplementIsNotInitialized() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 underlying = new MockERC20("DAI", "DAI", 8);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: DeployUtils.GT_ERC20,
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                oracle: IOracle(vm.randomAddress()),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(0)
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxFactory.MarketImplementIsNotInitialized.selector
            )
        );
        factory.createMarket(params);
        vm.stopPrank();
    }

    function testRevertByCantNotFindGtImplementation() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();
        factory.initMarketImplement(address(m));

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 underlying = new MockERC20("DAI", "DAI", 8);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: bytes32(0),
                admin: deployer,
                collateral: address(collateral),
                underlying: underlying,
                oracle: IOracle(vm.randomAddress()),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(0)
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxFactory.CantNotFindGtImplementation.selector
            )
        );
        factory.createMarket(params);
        vm.stopPrank();
    }

    function testPredictMarketAddress() public {
        vm.startPrank(deployer);
        // DeployUtils deployUtil = new DeployUtils();
        DeployUtils.Res memory res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );
        assertEq(
            res.factory.predictMarketAddress(
                address(res.collateral),
                res.underlying,
                marketConfig.openTime,
                marketConfig.maturity,
                marketConfig.initialLtv
            ),
            address(res.market)
        );
        vm.stopPrank();
    }

    function testInitMarketImplement() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();

        vm.expectEmit();
        emit ITermMaxFactory.InitializeMarketImplement(address(m));
        factory.initMarketImplement(address(m));
        assert(factory.marketImplement() == address(m));
        vm.stopPrank();
    }

    function testInitMarketImplementTwice() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();
        factory.initMarketImplement(address(m));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxFactory.MarketImplementInitialized.selector
            )
        );
        factory.initMarketImplement(address(m));
        assert(factory.marketImplement() == address(m));
        vm.stopPrank();
    }

    function testInitMarketImplementWithoutAuth(address sender) public {
        vm.startPrank(sender);
        TermMaxFactory factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();

        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                abi.encode(sender)
            )
        );
        factory.initMarketImplement(address(m));

        vm.stopPrank();
    }

    function testSetGtImplement() public {
        vm.startPrank(deployer);
        TermMaxFactory factory = new TermMaxFactory(deployer);
        GearingTokenWithERC20 gt = new GearingTokenWithERC20();
        string memory gtImplemtName = "gt-test";
        bytes32 key = keccak256(abi.encodePacked(gtImplemtName));
        vm.expectEmit();
        emit ITermMaxFactory.SetGtImplement(key, address(gt));
        factory.setGtImplement(gtImplemtName, address(gt));
        assert(factory.gtImplements(key) == address(gt));
        vm.stopPrank();
    }

    function testSetGtImplementWithoutAuth(address sender) public {
        vm.startPrank(sender);
        TermMaxFactory factory = new TermMaxFactory(deployer);
        GearingTokenWithERC20 gt = new GearingTokenWithERC20();
        string memory key = "gt-test";

        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                abi.encode(sender)
            )
        );
        factory.setGtImplement(key, address(gt));

        vm.stopPrank();
    }
}
