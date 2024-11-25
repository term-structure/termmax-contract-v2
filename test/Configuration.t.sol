// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface, GearingTokenWithERC20} from "../contracts/core/factory/TermMaxFactory.sol";
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

    function testSetTreasurer() public {
        vm.startPrank(deployer);
        address newTreasurer = vm.randomAddress();

        vm.expectEmit();
        emit ITermMaxMarket.UpdateTreasurer(newTreasurer);
        res.market.setTreasurer(newTreasurer);
        assert(res.market.config().treasurer == newTreasurer);

        assert(res.gt.getGtConfig().treasurer == newTreasurer);
        vm.stopPrank();
    }

    function testSetTreasurerWithoutAuth() public {
        vm.startPrank(sender);
        address newTreasurer = vm.randomAddress();

        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                abi.encode(sender)
            )
        );
        res.market.setTreasurer(newTreasurer);

        vm.stopPrank();
    }

    function testSetFee() public {
        vm.startPrank(deployer);

        uint32 lendFeeRatio = 0.01e8;
        uint32 minNLendFeeR = 0.02e8;
        uint32 borrowFeeRatio = 0.03e8;
        uint32 minNBorrowFeeR = 0.04e8;
        uint32 redeemFeeRatio = 0.05e8;
        uint32 issueFtFeeRatio = 0.06e8;
        uint32 lockingPercentage = 0.07e8;
        uint32 protocolFeeRatio = 0.08e8;
        vm.expectEmit();
        emit ITermMaxMarket.UpdateFeeRate(
            lendFeeRatio,
            minNLendFeeR,
            borrowFeeRatio,
            minNBorrowFeeR,
            redeemFeeRatio,
            issueFtFeeRatio,
            lockingPercentage,
            protocolFeeRatio
        );
        res.market.setFeeRate(
            lendFeeRatio,
            minNLendFeeR,
            borrowFeeRatio,
            minNBorrowFeeR,
            redeemFeeRatio,
            issueFtFeeRatio,
            lockingPercentage,
            protocolFeeRatio
        );
        assert(res.market.config().lendFeeRatio == lendFeeRatio);
        assert(res.market.config().minNLendFeeR == minNLendFeeR);
        assert(res.market.config().borrowFeeRatio == borrowFeeRatio);
        assert(res.market.config().minNBorrowFeeR == minNBorrowFeeR);
        assert(res.market.config().redeemFeeRatio == redeemFeeRatio);
        assert(res.market.config().issueFtFeeRatio == issueFtFeeRatio);
        assert(res.market.config().lockingPercentage == lockingPercentage);
        assert(res.market.config().protocolFeeRatio == protocolFeeRatio);
        vm.stopPrank();
    }

    function testSetFeeWithoutAuth() public {
        vm.startPrank(sender);

        uint32 lendFeeRatio = 0.01e8;
        uint32 minNLendFeeR = 0.02e8;
        uint32 borrowFeeRatio = 0.03e8;
        uint32 minNBorrowFeeR = 0.04e8;
        uint32 redeemFeeRatio = 0.05e8;
        uint32 issueFtFeeRatio = 0.06e8;
        uint32 lockingPercentage = 0.07e8;
        uint32 protocolFeeRatio = 0.08e8;

        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                abi.encode(sender)
            )
        );
        res.market.setFeeRate(
            lendFeeRatio,
            minNLendFeeR,
            borrowFeeRatio,
            minNBorrowFeeR,
            redeemFeeRatio,
            issueFtFeeRatio,
            lockingPercentage,
            protocolFeeRatio
        );
        vm.stopPrank();
    }

    function testSetLsf() public {
        vm.startPrank(deployer);
        uint32 lsf = 0.11e8;

        vm.expectEmit();
        emit ITermMaxMarket.UpdateLsf(lsf);
        res.market.setLsf(lsf);
        assert(res.market.config().lsf == lsf);

        vm.stopPrank();
    }

    function testSetLsfWithoutAuth() public {
        vm.startPrank(sender);
        uint32 lsf = 0.11e8;
        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                abi.encode(sender)
            )
        );
        res.market.setLsf(lsf);

        vm.stopPrank();
    }

    function testSetLsfWithoutInvalidLsf() public {
        vm.startPrank(deployer);
        uint32 lsf = 0;
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.InvalidLsf.selector, lsf)
        );
        res.market.setLsf(lsf);

        lsf = 1.01e8;
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.InvalidLsf.selector, lsf)
        );
        res.market.setLsf(lsf);

        vm.stopPrank();
    }
}
