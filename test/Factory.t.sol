// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import "../contracts/core/factory/TermMaxFactory.sol";

contract FactoryTest is Test {
    address deployer = vm.envAddress("FORK_DEPLOYER_ADDR");

    function setUp() public {}

    function testDeploy() public {
        vm.startPrank(deployer);
        uint32 maxLtv = 8.5e7;
        uint32 liquidationLtv = 9e7;

        TermMaxStorage.MarketConfig memory marketConfig;
        marketConfig.openTime = uint64(
            block.timestamp + Constants.SECONDS_IN_DAY
        );
        marketConfig.maturity = uint64(
            marketConfig.openTime + Constants.SECONDS_IN_MOUNTH
        );
        marketConfig.initialLtv = 9e7;
        marketConfig.deliverable = true;
        // DeployUtils deployUtil = new DeployUtils();
        DeployUtils.Res memory res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );
        console.log("gNft: ", address(res.gNft));
        vm.stopPrank();
    }
}
