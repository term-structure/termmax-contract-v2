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
    MarketConfig marketConfig;
    DeployUtils.Res res;

    function setUp() public {
        string memory testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/testdata.json")
        );

        vm.startPrank(deployer);
        testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/testdata.json")
        );

        marketConfig = JSONLoader.getMarketConfigFromJson(
            treasurer,
            testdata,
            ".marketConfig"
        );
        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );

        vm.warp(
            vm.parseUint(
                vm.parseJsonString(testdata, ".marketConfig.currentTime")
            )
        );
        vm.stopPrank();
    }

    function testUpdateMarketConfig() public {
        vm.startPrank(deployer);

        MarketConfig memory newConfig = res.market.config();
        newConfig.treasurer = vm.randomAddress();
        newConfig.lsf = 0.11e8;
        newConfig.minApr = -0.3e8;
        newConfig.lendFeeRatio = 0.01e8;
        newConfig.minNLendFeeR = 0.02e8;
        newConfig.borrowFeeRatio = 0.03e8;
        newConfig.minNBorrowFeeR = 0.04e8;
        newConfig.redeemFeeRatio = 0.05e8;
        newConfig.issueFtFeeRatio = 0.06e8;
        newConfig.lockingPercentage = 0.07e8;
        newConfig.protocolFeeRatio = 0.08e8;

        vm.expectEmit();
        emit ITermMaxMarket.UpdateMarketConfig(newConfig);
        res.market.updateMarketConfig(newConfig);

        MarketConfig memory updatedConfig = res.market.config();
        assertEq(updatedConfig.treasurer, newConfig.treasurer);
        assertEq(updatedConfig.lsf, newConfig.lsf);
        assertEq(updatedConfig.minApr, newConfig.minApr);
        assertEq(updatedConfig.lendFeeRatio, newConfig.lendFeeRatio);
        assertEq(updatedConfig.minNLendFeeR, newConfig.minNLendFeeR);
        assertEq(updatedConfig.borrowFeeRatio, newConfig.borrowFeeRatio);
        assertEq(updatedConfig.minNBorrowFeeR, newConfig.minNBorrowFeeR);
        assertEq(updatedConfig.redeemFeeRatio, newConfig.redeemFeeRatio);
        assertEq(updatedConfig.issueFtFeeRatio, newConfig.issueFtFeeRatio);
        assertEq(updatedConfig.lockingPercentage, newConfig.lockingPercentage);
        assertEq(updatedConfig.protocolFeeRatio, newConfig.protocolFeeRatio);

        // Check GT treasurer is updated
        assert(res.gt.getGtConfig().treasurer == newConfig.treasurer);

        vm.stopPrank();
    }

    function testUpdateMarketConfigWithoutAuth() public {
        vm.startPrank(sender);

        MarketConfig memory newConfig = res.market.config();
        newConfig.treasurer = vm.randomAddress();
        newConfig.lsf = 0.11e8;
        newConfig.lendFeeRatio = 0.01e8;
        newConfig.minNLendFeeR = 0.02e8;
        newConfig.borrowFeeRatio = 0.03e8;
        newConfig.minNBorrowFeeR = 0.04e8;
        newConfig.redeemFeeRatio = 0.05e8;
        newConfig.issueFtFeeRatio = 0.06e8;
        newConfig.lockingPercentage = 0.07e8;
        newConfig.protocolFeeRatio = 0.08e8;

        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                abi.encode(sender)
            )
        );
        res.market.updateMarketConfig(newConfig);

        vm.stopPrank();
    }

    function testUpdateMarketConfigInvalidLsf() public {
        vm.startPrank(deployer);

        MarketConfig memory newConfig = res.market.config();
        newConfig.lsf = uint32(Constants.DECIMAL_BASE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.InvalidLsf.selector,
                newConfig.lsf
            )
        );
        res.market.updateMarketConfig(newConfig);

        newConfig.lsf = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.InvalidLsf.selector,
                newConfig.lsf
            )
        );
        res.market.updateMarketConfig(newConfig);

        vm.stopPrank();
    }

    function testSetProviderWhitelist() public {
        address provider = vm.randomAddress();
        
        assertTrue(res.market.providerWhitelist(address(0)), "All providers should be whitelisted by default");
        // Test unauthorized access
        vm.startPrank(sender);
        vm.expectRevert(abi.encodePacked(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                abi.encode(sender)
            ));
        res.market.setProviderWhitelist(provider, true);
        vm.stopPrank();

        // Test setting whitelist as owner
        vm.startPrank(deployer);
        vm.expectEmit();
        emit ITermMaxMarket.UpdateProviderWhitelist(provider, true);
        res.market.setProviderWhitelist(provider, true);
        assertTrue(res.market.providerWhitelist(provider), "Provider should be whitelisted");

        // Test removing from whitelist
        vm.expectEmit();
        emit ITermMaxMarket.UpdateProviderWhitelist(provider, false);
        res.market.setProviderWhitelist(provider, false);
        assertFalse(res.market.providerWhitelist(provider), "Provider should not be whitelisted");
        vm.stopPrank();
    }

    function testSetMultipleProviderWhitelist() public {
        address[] memory providers = new address[](3);
        providers[0] = vm.randomAddress();
        providers[1] = vm.randomAddress();
        providers[2] = vm.randomAddress();

        vm.startPrank(deployer);
        
        // Whitelist multiple providers
        for (uint i = 0; i < providers.length; i++) {
            res.market.setProviderWhitelist(providers[i], true);
            assertTrue(res.market.providerWhitelist(providers[i]), "Provider should be whitelisted");
        }

        // Verify each provider's status
        for (uint i = 0; i < providers.length; i++) {
            assertTrue(res.market.providerWhitelist(providers[i]), "Provider should remain whitelisted");
        }

        // Remove whitelist status
        for (uint i = 0; i < providers.length; i++) {
            res.market.setProviderWhitelist(providers[i], false);
            assertFalse(res.market.providerWhitelist(providers[i]), "Provider should not be whitelisted");
        }
        vm.stopPrank();
    }
}
