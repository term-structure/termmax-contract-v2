// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import "../contracts/core/factory/TermMaxFactory.sol";

contract FactoryTest is Test {
    ITermMaxMarket market;

    TermMaxFactory factory;

    address deployer = vm.envAddress("FORK_DEPLOYER_ADDR");

    function setUp() public {
        vm.startPrank(deployer);
        factory = new TermMaxFactory(deployer);
        console.log("Factory deploy at:", address(factory));
        factory.initMarketBytes(type(TermMaxMarket).creationCode);
        vm.stopPrank();
    }

    function testDeploy() public {
        vm.startPrank(deployer);
        MockERC20 collateral = new MockERC20("ETH", "ETH");
        MockERC20 cash = new MockERC20("DAI", "DAI");
        MockPriceFeed priceFeed = new MockPriceFeed();
        uint32 liquidationLtv = 9e7;
        uint32 maxLtv = 8.5e7;
        TermMaxStorage.MarketConfig memory marketConfig;
        marketConfig.openTime = uint64(
            block.timestamp + Constants.SECONDS_IN_DAY
        );
        marketConfig.maturity =
            marketConfig.openTime +
            Constants.SECONDS_IN_MOUNTH;
        marketConfig.initialLtv = 9e7;
        marketConfig.deliverable = true;

        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams(
                collateral,
                cash,
                priceFeed,
                maxLtv,
                liquidationLtv,
                marketConfig
            );

        market = ITermMaxMarket(factory.createERC20Market(params));
        console.log("Market deploy at:", address(market));
        vm.stopPrank();
    }
}
