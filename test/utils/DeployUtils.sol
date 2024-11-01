// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {ITermMaxMarket, TermMaxMarket, Constants} from "../../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";
import "../../contracts/core/factory/TermMaxFactory.sol";

library DeployUtils {
    struct Res {
        TermMaxFactory factory;
        ITermMaxMarket market;
        IMintableERC20 ft;
        IMintableERC20 xt;
        IMintableERC20 lpFt;
        IMintableERC20 lpXt;
        IGearingNft gNft;
        AggregatorV3Interface underlyingOracle;
        AggregatorV3Interface collateralOracle;
        MockERC20 collateral;
        MockERC20 underlying;
    }

    function deployMarket(
        address deployer,
        TermMaxStorage.MarketConfig memory marketConfig,
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
        console.log("gNft deploy at: ", address(res.gNft));
        (res.ft, res.xt, res.lpFt, res.lpXt, res.gNft, , ) = res
            .market
            .tokens();
    }
}
