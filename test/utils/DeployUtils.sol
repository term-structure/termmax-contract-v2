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
        AggregatorV3Interface underlyingOracle;
        AggregatorV3Interface collateralOracle;
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
        console.log("Factory deploy at:", address(res.factory));
        res.factory.initMarketBytes(type(TermMaxMarket).creationCode);

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
                admin: deployer,
                collateral: res.collateral,
                underlying: res.underlying,
                collateralOracle: res.collateralOracle,
                underlyingOracle: res.underlyingOracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig
            });

        res.market = ITermMaxMarket(res.factory.createERC20Market(params));
        console.log("Market deploy at:", address(res.market));
        console.log("gt deploy at: ", address(res.gt));
        (res.ft, res.xt, res.lpFt, res.lpXt, res.gt, , ) = res
            .market
            .tokens();
    }

    function deployRouter(address deployer) internal returns (TermMaxRouter router) {
        address implementation = address(new TermMaxRouter());

        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, deployer);
        address proxy = address(new ERC1967Proxy(implementation, data));

        router = TermMaxRouter(proxy);
        console.log("TermMaxRouter deploy at:", address(router));
    }
}
