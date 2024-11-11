// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../../contracts/core/factory/TermMaxFactory.sol";
import {TermMaxRouter} from "../../contracts/router/TermMaxRouter.sol";
import "../../contracts/core/storage/TermMaxStorage.sol";

library DeployUtils {
    struct Res {
        TermMaxFactory factory;
        ITermMaxMarket market;
        IMintableERC20 ft;
        IMintableERC20 xt;
        IMintableERC20 lpFt;
        IMintableERC20 lpXt;
        IGearingToken gt;
        MockPriceFeed underlyingOracle;
        MockPriceFeed collateralOracle;
        MockERC20 collateral;
        MockERC20 underlying;
    }

    function deployMarket(
        address deployer,
        MarketConfig memory marketConfig,
        uint32 maxLtv,
        uint32 liquidationLtv
    ) internal returns (Res memory res) {
        res.factory = new TermMaxFactory(deployer);

        TermMaxMarket m = new TermMaxMarket();
        res.factory.initMarketImplement(address(m));

        res.collateral = new MockERC20("ETH", "ETH", 18);
        res.underlying = new MockERC20("DAI", "DAI", 8);

        res.underlyingOracle = new MockPriceFeed(deployer);
        res.collateralOracle = new MockPriceFeed(deployer);

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
                gtKey: res.factory.GT_ERC20(),
                admin: deployer,
                collateral: address(res.collateral),
                underlying: res.underlying,
                underlyingOracle: res.underlyingOracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(res.collateralOracle)
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
                underlyingOracle: res.underlyingOracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: liquidatable,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(res.collateralOracle)
            });

        res.market = ITermMaxMarket(res.factory.createMarket(params));
        (res.ft, res.xt, res.lpFt, res.lpXt, res.gt, , ) = res.market.tokens();
    }

    function deployRouter(
        address deployer
    ) internal returns (TermMaxRouter router) {
        address implementation = address(new TermMaxRouter());

        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, deployer);
        address proxy = address(new ERC1967Proxy(implementation, data));

        router = TermMaxRouter(proxy);
    }
}
