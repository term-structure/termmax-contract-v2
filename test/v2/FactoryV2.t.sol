// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";

import {ITermMaxMarketV2, TermMaxMarketV2, Constants, MarketErrors} from "contracts/v2/TermMaxMarketV2.sol";
import {MockERC20, ERC20} from "contracts/v1/test/MockERC20.sol";

import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {IMintableERC20} from "contracts/v1/tokens/MintableERC20.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {
    GearingTokenWithERC20V2,
    GearingTokenEvents,
    GearingTokenEventsV2,
    GtConfig
} from "contracts/v2/tokens/GearingTokenWithERC20V2.sol";
import {
    ITermMaxFactory,
    TermMaxFactoryV2,
    FactoryErrors,
    FactoryEvents,
    FactoryEventsV2
} from "contracts/v2/factory/TermMaxFactoryV2.sol";
import {IOracleV2, OracleAggregatorV2, AggregatorV3Interface} from "contracts/v2/oracle/OracleAggregatorV2.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {
    VaultInitialParams,
    MarketConfig,
    MarketInitialParams,
    LoanConfig,
    OrderConfig,
    CurveCuts
} from "contracts/v1/storage/TermMaxStorage.sol";

contract FactoryTestV2 is Test {
    address deployer = vm.randomAddress();

    address treasurer = vm.randomAddress();
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;
    MarketConfig marketConfig;

    function setUp() public {
        string memory testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
    }

    function testDeploy() public {
        vm.startPrank(deployer);
        DeployUtils.Res memory res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        address predictedMarketAddress = res.factory.predictMarketAddress(
            deployer, address(res.collateral), address(res.debt), marketConfig.maturity, 0
        );
        assert(address(res.market) == predictedMarketAddress);

        assert(
            keccak256(abi.encode(ITermMaxMarketV2(address(res.market)).name()))
                == keccak256(abi.encode("Termmax Market:DAI-ETH"))
        );

        assert(keccak256(abi.encode(res.market.config())) == keccak256(abi.encode(marketConfig)));
        GtConfig memory gtConfig = res.gt.getGtConfig();
        assert(gtConfig.maturity == marketConfig.maturity);
        assert(gtConfig.loanConfig.maxLtv == maxLtv);
        assert(gtConfig.loanConfig.liquidationLtv == liquidationLtv);
        assert(gtConfig.loanConfig.liquidatable == true);
        assert(gtConfig.collateral == address(res.collateral));
        assert(gtConfig.debtToken == res.debt);
        assert(gtConfig.ft == res.ft);
        assert(GearingTokenWithERC20V2(address(res.gt)).collateralCapacity() == type(uint256).max);
        vm.stopPrank();
    }

    function testDeployRepeatedly() public {
        vm.startPrank(deployer);
        DeployUtils.Res memory res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        LoanConfig memory loanConfig = res.gt.getGtConfig().loanConfig;
        vm.expectRevert(abi.encodeWithSignature("FailedDeployment()"));
        res.factory.createMarket(
            DeployUtils.GT_ERC20,
            MarketInitialParams({
                collateral: address(res.collateral),
                debtToken: res.debt,
                admin: deployer,
                gtImplementation: address(0),
                marketConfig: marketConfig,
                loanConfig: loanConfig,
                gtInitalParams: abi.encode(type(uint256).max),
                tokenName: "test",
                tokenSymbol: "test"
            }),
            0
        );
        vm.stopPrank();
    }

    function testDeployMarketWithInvalidParams() public {
        vm.startPrank(deployer);
        TermMaxFactoryV2 factory = DeployUtils.deployFactory(deployer);

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 debt = new MockERC20("DAI", "DAI", 8);

        MarketInitialParams memory params = MarketInitialParams({
            collateral: address(collateral),
            debtToken: debt,
            admin: deployer,
            gtImplementation: factory.gtImplements(DeployUtils.GT_ERC20),
            marketConfig: marketConfig,
            loanConfig: LoanConfig({
                maxLtv: maxLtv,
                liquidationLtv: liquidationLtv,
                liquidatable: true,
                oracle: IOracle(vm.randomAddress())
            }),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "test",
            tokenSymbol: "test"
        });
        uint64 maturity = marketConfig.maturity;
        vm.warp(maturity + 1 days);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.InvalidMaturity.selector));
        factory.createMarket(DeployUtils.GT_ERC20, params, 0);

        vm.warp(maturity - 1 days);
        params.marketConfig.feeConfig.borrowTakerFeeRatio = Constants.MAX_FEE_RATIO;
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.FeeTooHigh.selector));
        factory.createMarket(DeployUtils.GT_ERC20, params, 0);

        params.marketConfig.feeConfig.borrowTakerFeeRatio = 0;
        params.marketConfig.feeConfig.mintGtFeeRef = uint32(Constants.DECIMAL_BASE * 5 + 1);
        vm.expectRevert(abi.encodeWithSelector(MarketErrors.FeeTooHigh.selector));
        factory.createMarket(DeployUtils.GT_ERC20, params, 0);

        params.marketConfig.feeConfig.mintGtFeeRef = 0;
        address predictMarketAddress =
            factory.predictMarketAddress(deployer, address(collateral), address(debt), maturity, 0);
        vm.expectEmit();
        emit GearingTokenEventsV2.GearingTokenInitialized(
            predictMarketAddress, "GT:test", "GT:test", abi.encode(type(uint256).max)
        );
        emit GearingTokenWithERC20V2.CollateralCapacityUpdated(type(uint256).max);
        emit FactoryEventsV2.MarketCreated(predictMarketAddress, address(collateral), debt, params);
        factory.createMarket(DeployUtils.GT_ERC20, params, 0);
        vm.stopPrank();
    }

    function testLiquidationLtvMustBeGreaterThanMaxLtv() public {
        vm.startPrank(deployer);
        TermMaxFactoryV2 factory = DeployUtils.deployFactory(deployer);

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 debt = new MockERC20("DAI", "DAI", 8);

        maxLtv = 3;
        liquidationLtv = 2;

        MarketInitialParams memory params = MarketInitialParams({
            collateral: address(collateral),
            debtToken: debt,
            admin: deployer,
            gtImplementation: address(0),
            marketConfig: marketConfig,
            loanConfig: LoanConfig({
                maxLtv: maxLtv,
                liquidationLtv: liquidationLtv,
                liquidatable: true,
                oracle: IOracle(vm.randomAddress())
            }),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "test",
            tokenSymbol: "test"
        });

        vm.expectRevert(abi.encodeWithSignature("LiquidationLtvMustBeGreaterThanMaxLtv()"));
        factory.createMarket(DeployUtils.GT_ERC20, params, 0);

        vm.stopPrank();
    }

    function testRevertByCantNotFindGtImplementation() public {
        vm.startPrank(deployer);
        TermMaxFactoryV2 factory = DeployUtils.deployFactory(deployer);

        MockERC20 collateral = new MockERC20("ETH", "ETH", 18);
        MockERC20 debt = new MockERC20("DAI", "DAI", 8);

        vm.expectRevert(abi.encodeWithSelector(FactoryErrors.CantNotFindGtImplementation.selector));
        factory.createMarket(
            bytes32(0),
            MarketInitialParams({
                collateral: address(collateral),
                debtToken: debt,
                admin: deployer,
                gtImplementation: address(0),
                marketConfig: marketConfig,
                loanConfig: LoanConfig({
                    maxLtv: maxLtv,
                    liquidationLtv: liquidationLtv,
                    liquidatable: true,
                    oracle: IOracle(vm.randomAddress())
                }),
                gtInitalParams: abi.encode(type(uint256).max),
                tokenName: "test",
                tokenSymbol: "test"
            }),
            0
        );
        vm.stopPrank();
    }

    function testSetGtImplement() public {
        vm.startPrank(deployer);
        TermMaxFactoryV2 factory = DeployUtils.deployFactory(deployer);
        GearingTokenWithERC20V2 gt = new GearingTokenWithERC20V2();
        string memory gtImplemtName = "gt-test";
        bytes32 key = keccak256(abi.encodePacked(gtImplemtName));
        vm.expectEmit();
        emit FactoryEvents.SetGtImplement(key, address(gt));
        factory.setGtImplement(gtImplemtName, address(gt));
        assert(factory.gtImplements(key) == address(gt));
        vm.stopPrank();
    }

    function testSetGtImplementWithoutAuth() public {
        address sender = vm.randomAddress();
        vm.startPrank(sender);
        TermMaxFactoryV2 factory = DeployUtils.deployFactory(deployer);
        GearingTokenWithERC20V2 gt = new GearingTokenWithERC20V2();
        string memory key = "gt-test";

        vm.expectRevert(abi.encodePacked(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), abi.encode(sender)));
        factory.setGtImplement(key, address(gt));

        vm.stopPrank();
    }

    function testInvalidMarketImplementation() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryErrors.InvalidImplementation.selector));
        new TermMaxFactoryV2(deployer, address(0));
    }
}
