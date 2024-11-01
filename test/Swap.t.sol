// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import "../contracts/core/factory/TermMaxFactory.sol";

contract SwapTest is Test {
    address deployer = vm.envAddress("FORK_DEPLOYER_ADDR");

    DeployUtils.Res res;

    TermMaxStorage.MarketConfig marketConfig;

    address sender = vm.randomAddress();

    function setUp() public {
        vm.startPrank(deployer);
        uint32 maxLtv = 0.85e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig.openTime = uint64(block.timestamp);
        marketConfig.maturity = uint64(
            marketConfig.openTime + Constants.SECONDS_IN_DAY * 30
        );
        marketConfig.initialLtv = 0.9e8;
        marketConfig.apr = 0.1e8;
        marketConfig.lsf = 0.5e8;
        // DeployUtils deployUtil = new DeployUtils();
        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );

        uint amount = 10000e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(res.market), amount);

        res.market.provideLiquidity(amount);
        vm.stopPrank();
    }

    function testBuyFT() public {
        vm.startPrank(sender);
        // uint amount = 10000e8;
        (uint256 pFt, uint256 pXt) = SwapUtils.getPrice(res);
        console.log(pFt);
        console.log(pXt);
        console.log((pXt * 9) / 10 + pFt);

        vm.stopPrank();
    }
}
