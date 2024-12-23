// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, GearingTokenWithERC20} from "../contracts/core/factory/TermMaxFactory.sol";
import "../contracts/core/storage/TermMaxStorage.sol";

contract ConfigurationTest is Test {
    address deployer = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;
    TokenPairConfig tokenPairConfig;
    MarketConfig marketConfig;
    DeployUtils.Res res;

    function setUp() public {
        string memory testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        tokenPairConfig = JSONLoader.getTokenPairConfigFromJson(treasurer, testdata, ".tokenPairConfig");
        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        res = DeployUtils.deployMarket(deployer, tokenPairConfig, marketConfig, maxLtv, liquidationLtv);

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));
        vm.stopPrank();
    }

    function testUpdateMarketConfig() public {
        vm.startPrank(deployer);

        MarketConfig memory newConfig = res.market.config();
        newConfig.lendFeeRatio = 0.01e8;
        newConfig.minNLendFeeR = 0.02e8;
        newConfig.borrowFeeRatio = 0.03e8;
        newConfig.minNBorrowFeeR = 0.04e8;

        vm.expectEmit();
        emit ITermMaxMarket.UpdateMarketConfig(newConfig);
        res.market.updateMarketConfig(newConfig, 0, 0);

        MarketConfig memory updatedConfig = res.market.config();
        assertEq(updatedConfig.lendFeeRatio, newConfig.lendFeeRatio);
        assertEq(updatedConfig.minNLendFeeR, newConfig.minNLendFeeR);
        assertEq(updatedConfig.borrowFeeRatio, newConfig.borrowFeeRatio);
        assertEq(updatedConfig.minNBorrowFeeR, newConfig.minNBorrowFeeR);

        // Check GT treasurer is updated
        assert(res.gt.getGtConfig().treasurer == newConfig.treasurer);

        vm.stopPrank();
    }

    function testUpdateMarketConfigWithoutAuth() public {
        vm.startPrank(sender);

        MarketConfig memory newConfig = res.market.config();
        newConfig.treasurer = vm.randomAddress();
        newConfig.lendFeeRatio = 0.01e8;
        newConfig.minNLendFeeR = 0.02e8;
        newConfig.borrowFeeRatio = 0.03e8;
        newConfig.minNBorrowFeeR = 0.04e8;

        vm.expectRevert(abi.encodePacked(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), abi.encode(sender)));
        res.market.updateMarketConfig(newConfig, 0, 0);

        vm.stopPrank();
    }

    function testSetProviderWhitelist() public {
        address provider = vm.randomAddress();

        // Test unauthorized access
        vm.startPrank(sender);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), abi.encode(sender)));
        res.market.setProvider(provider);
        vm.stopPrank();

        // Test setting whitelist as owner
        vm.startPrank(deployer);
        vm.expectEmit();
        emit ITermMaxMarket.UpdateProvider(provider);
        res.market.setProvider(provider);

        vm.stopPrank();
    }
}
