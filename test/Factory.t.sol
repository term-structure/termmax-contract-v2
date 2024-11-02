// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../contracts/core/factory/TermMaxFactory.sol";
import "../contracts/core/storage/TermMaxStorage.sol";

contract FactoryTest is Test {
    address deployer = vm.envAddress("FORK_DEPLOYER_ADDR");

    function setUp() public {}

    function testDeploy() public {
        vm.startPrank(deployer);
        uint32 maxLtv = 8.5e7;
        uint32 liquidationLtv = 9e7;

        MarketConfig memory marketConfig;
        marketConfig.openTime = uint64(
            block.timestamp + Constants.SECONDS_IN_DAY
        );
        marketConfig.maturity = uint64(
            marketConfig.openTime + Constants.SECONDS_IN_DAY * 30
        );
        marketConfig.initialLtv = 9e7;
        // DeployUtils deployUtil = new DeployUtils();
        DeployUtils.Res memory res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );
        console.log("gt: ", address(res.gt));
        vm.stopPrank();
    }
}
