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

    DeployUtils.Res res;

    function setUp() public {
        vm.startPrank(deployer);
        uint32 maxLtv = 0.85e8;
        uint32 liquidationLtv = 0.9e8;

        TermMaxStorage.MarketConfig memory marketConfig;
        marketConfig.openTime = uint64(block.timestamp);
        marketConfig.maturity =
            marketConfig.openTime +
            Constants.SECONDS_IN_MOUNTH;
        marketConfig.initialLtv = 0.9e8;
        marketConfig.apr = 0.1e8;
        marketConfig.deliverable = true;
        // DeployUtils deployUtil = new DeployUtils();
        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );
        console.log("gNft: ", address(res.gNft));
        vm.stopPrank();
    }

    function testProvideLiquidity() public {
        address sender = vm.randomAddress();
        vm.startPrank(sender);
        uint amount = 10000e8;
        res.underlying.mint(sender, amount);
        res.underlying.approve(address(res.market), amount);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            amount
        );
        console.log(lpFtOutAmt);
        console.log(lpXtOutAmt);
        console.log(res.ft.balanceOf(address(res.market)));
        console.log(res.xt.balanceOf(address(res.market)));
        vm.stopPrank();
    }
}
