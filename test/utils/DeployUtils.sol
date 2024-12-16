// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ITermMaxMarket, TermMaxMarket, Constants, IERC20} from "../../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken} from "../../contracts/core/factory/TermMaxFactory.sol";
import {TermMaxRouter} from "../../contracts/router/TermMaxRouter.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import {AccessManager} from "contracts/access/AccessManager.sol";
import "../../contracts/core/storage/TermMaxStorage.sol";

library DeployUtils {
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");
    struct Res {
        TermMaxFactory factory;
        ITermMaxMarket market;
        MarketConfig marketConfig;
        IMintableERC20 ft;
        IMintableERC20 xt;
        IMintableERC20 lpFt;
        IMintableERC20 lpXt;
        IGearingToken gt;
        MockPriceFeed underlyingOracle;
        MockPriceFeed collateralOracle;
        OracleAggregator oracle;
        MockERC20 collateral;
        MockERC20 underlying;
    }

    function deployMarket(
        address deployer,
        MarketConfig memory marketConfig,
        uint32 maxLtv,
        uint32 liquidationLtv
    ) internal returns (Res memory res) {
        res.factory = deployFactory(deployer);

        res.collateral = new MockERC20("ETH", "ETH", 18);
        res.underlying = new MockERC20("DAI", "DAI", 8);

        res.underlyingOracle = new MockPriceFeed(deployer);
        res.collateralOracle = new MockPriceFeed(deployer);
        res.oracle = deployOracle(deployer);

        res.oracle.setOracle(address(res.underlying), IOracle.Oracle(res.underlyingOracle,res.underlyingOracle, 365 days));
        res.oracle.setOracle(address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 365 days));

        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 1,
            answer: int(1e1 ** res.collateralOracle.decimals()),
            startedAt: 0,
            updatedAt: 0,
            answeredInRound: 0
        });
        res.collateralOracle.updateRoundData(roundData);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: GT_ERC20,
                admin: deployer,
                collateral: address(res.collateral),
                underlying: res.underlying,
                oracle: res.oracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(type(uint256).max)
            });
        res.marketConfig = marketConfig;
        res.market = ITermMaxMarket(res.factory.createMarket(params));
        (res.ft, res.xt, res.lpFt, res.lpXt, res.gt, , ) = res.market.tokens();
    }

    function deployMarket(
        address deployer,
        MarketConfig memory marketConfig,
        uint32 maxLtv,
        uint32 liquidationLtv,
        address collateral,
        address underlying
    ) internal returns (Res memory res) {
        res.factory = new TermMaxFactory(deployer);
        res.marketConfig = marketConfig;

        TermMaxMarket m = new TermMaxMarket();
        res.factory.initMarketImplement(address(m));

        res.collateral = MockERC20(collateral);
        res.underlying = MockERC20(underlying);

        res.underlyingOracle = new MockPriceFeed(deployer);
        res.collateralOracle = new MockPriceFeed(deployer);

        res.oracle = deployOracle(deployer);
        res.oracle.setOracle(address(res.underlying), IOracle.Oracle(res.underlyingOracle, res.underlyingOracle, 7 days));
        res.oracle.setOracle(address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 7 days));

        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 1,
            answer: int(1e1 ** res.collateralOracle.decimals()),
            startedAt: 0,
            updatedAt: 0,
            answeredInRound: 0
        });
        res.collateralOracle.updateRoundData(roundData);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: GT_ERC20,
                admin: deployer,
                collateral: address(res.collateral),
                underlying: res.underlying,
                oracle: res.oracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(type(uint256).max)
            });

        res.market = ITermMaxMarket(res.factory.createMarket(params));
        (res.ft, res.xt, res.lpFt, res.lpXt, res.gt, , ) = res.market.tokens();
    }

    function deploySpecialMarket(
        address deployer,
        TermMaxFactory factory,
        bytes32 gtKey,
        MarketConfig memory marketConfig,
        uint32 maxLtv,
        uint32 liquidationLtv,
        bool liquidatable
    ) internal returns (Res memory res) {
        res.factory = factory;

        res.collateral = new MockERC20("ETH", "ETH", 18);
        res.underlying = new MockERC20("DAI", "DAI", 8);

        res.underlyingOracle = new MockPriceFeed(deployer);
        res.collateralOracle = new MockPriceFeed(deployer);

        res.oracle = deployOracle(deployer);
        res.oracle.setOracle(address(res.underlying), IOracle.Oracle(res.underlyingOracle,res.underlyingOracle, 7 days));
        res.oracle.setOracle(address(res.collateral), IOracle.Oracle(res.collateralOracle,res.collateralOracle, 7 days));

        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 1,
            answer: int(1e1 ** res.collateralOracle.decimals()),
            startedAt: 0,
            updatedAt: 0,
            answeredInRound: 0
        });
        MockPriceFeed(address(res.collateralOracle)).updateRoundData(roundData);

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: gtKey,
                admin: deployer,
                collateral: address(res.collateral),
                underlying: res.underlying,
                oracle: res.oracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: liquidatable,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(type(uint256).max)
            });

        res.market = ITermMaxMarket(res.factory.createMarket(params));
        (res.ft, res.xt, res.lpFt, res.lpXt, res.gt, , ) = res.market.tokens();
    }

    function deployFactory(address admin) internal returns (TermMaxFactory factory) {
        factory = new TermMaxFactory(admin);
        TermMaxMarket m = new TermMaxMarket();
        factory.initMarketImplement(address(m));
    }

    function deployOracle(address admin) internal returns (OracleAggregator oracle) {
        OracleAggregator implementation = new OracleAggregator();
        bytes memory data = abi.encodeCall(OracleAggregator.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            data
        );
        oracle = OracleAggregator(address(proxy));
    }

    function deployRouter(address admin) internal returns (TermMaxRouter router) {
        TermMaxRouter implementation = new TermMaxRouter();
        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        router = TermMaxRouter(address(proxy));
    }

    function deployAccessManager(address admin) internal returns (AccessManager accessManager) {
        AccessManager implementation = new AccessManager();
        bytes memory data = abi.encodeCall(AccessManager.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        accessManager = AccessManager(address(proxy));
    }
}
