// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "contracts/v1/lib/Constants.sol";
import {
    ITermMaxMarketV2, TermMaxMarketV2, Constants, MarketErrors, MarketEvents
} from "contracts/v2/TermMaxMarketV2.sol";
import {MockERC20, ERC20} from "contracts/v1/test/MockERC20.sol";

import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {IMintableERC20} from "contracts/v1/tokens/MintableERC20.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {
    GearingTokenWithERC20V2,
    GearingTokenEvents,
    GearingTokenErrors,
    GearingTokenEventsV2,
    GtConfig
} from "contracts/v2/tokens/GearingTokenWithERC20V2.sol";
import {
    ITermMaxFactory,
    TermMaxFactoryV2,
    FactoryErrors,
    FactoryEvents,
    FactoryEventsV2
} from "contracts/v2/factory/TermMaxFactoryV2.sol";
import {IOracleV2, OracleAggregatorV2, AggregatorV3Interface} from "contracts/v2/oracle/OracleAggregatorV2.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {
    VaultInitialParams,
    MarketConfig,
    MarketInitialParams,
    LoanConfig,
    OrderConfig,
    CurveCuts
} from "contracts/v1/storage/TermMaxStorage.sol";
import {MockFlashLoanReceiver} from "contracts/v1/test/MockFlashLoanReceiver.sol";
import {MockFlashRepayerV2} from "contracts/v2/test/MockFlashRepayerV2.sol";
import {ISwapCallback} from "contracts/v1/ISwapCallback.sol";
import {
    TermMaxRouterV2,
    ITermMaxRouterV2,
    SwapUnit,
    RouterErrors,
    RouterEvents,
    SwapPath
} from "contracts/v2/router/TermMaxRouterV2.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {MockSwapAdapterV2} from "contracts/v2/test/MockSwapAdapterV2.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {TermMaxSwapData, TermMaxSwapAdapter} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
import {TermMaxOrderV2, OrderInitialParams} from "contracts/v2/TermMaxOrderV2.sol";
import {MakerHelper, MakerHelperErrors} from "contracts/v2/router/MakerHelper.sol";
import {DelegateAble} from "contracts/v2/lib/DelegateAble.sol";

contract MakerHelperTest is Test {
    using JSONLoader for *;
    using SafeCast for *;

    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address maker = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    address pool = vm.randomAddress();

    DeployUtils.Res res2;

    MakerHelper makerHelper;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order = TermMaxOrderV2(
            address(
                res.market.createOrder(
                    maker, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts
                )
            )
        );

        OrderInitialParams memory orderParams;
        orderParams.maker = maker;
        orderParams.orderConfig = orderConfig;
        uint256 amount = 150e8;
        orderParams.virtualXtReserve = amount;
        res.order = TermMaxOrderV2(address(res.market.createOrder(orderParams)));

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        res.debt.mint(deployer, amount);
        res.debt.approve(address(res.market), amount);
        res.market.mint(deployer, amount);
        res.ft.transfer(address(res.order), amount);
        res.xt.transfer(address(res.order), amount);

        address implementation = address(new MakerHelper());
        bytes memory data = abi.encodeCall(MakerHelper.initialize, deployer);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        makerHelper = MakerHelper(address(proxy));

        vm.stopPrank();

        vm.prank(maker);
        res.order.updateOrder(orderConfig, 0, 0);
    }

    function testPlaceOrderForV1() public {
        vm.startPrank(sender);

        uint256 debtTokenToDeposit = 1e8;
        uint128 ftToDeposit = 2e8;
        uint128 xtToDeposit = 0;

        res.debt.mint(sender, debtTokenToDeposit);
        deal(address(res.ft), sender, ftToDeposit);
        res.debt.approve(address(makerHelper), debtTokenToDeposit);
        res.ft.approve(address(makerHelper), ftToDeposit);
        res.xt.approve(address(makerHelper), xtToDeposit);
        uint256 collateralToMintGt = 1e18;
        res.collateral.mint(sender, collateralToMintGt);
        res.collateral.approve(address(makerHelper), collateralToMintGt);

        (ITermMaxOrder order, uint256 gtId) = makerHelper.placeOrderForV1(
            res.market, sender, collateralToMintGt, debtTokenToDeposit, ftToDeposit, xtToDeposit, orderConfig
        );

        assertEq(gtId, 1);
        assertEq(order.maker(), sender);
        assertEq(res.ft.balanceOf(address(order)), ftToDeposit + debtTokenToDeposit);
        assertEq(res.xt.balanceOf(address(order)), xtToDeposit + debtTokenToDeposit);

        vm.stopPrank();
    }

    function testPlaceOrderForV2(uint256 salt) public {
        vm.startPrank(sender);

        uint256 debtTokenToDeposit = 1e8;
        uint128 ftToDeposit = 2e8;
        uint128 xtToDeposit = 0;

        res.debt.mint(sender, debtTokenToDeposit);
        deal(address(res.ft), sender, ftToDeposit);
        res.debt.approve(address(makerHelper), debtTokenToDeposit);
        res.ft.approve(address(makerHelper), ftToDeposit);
        res.xt.approve(address(makerHelper), xtToDeposit);
        uint256 collateralToMintGt = 1e18;
        res.collateral.mint(sender, collateralToMintGt);
        res.collateral.approve(address(makerHelper), collateralToMintGt);

        OrderInitialParams memory initialParams;
        initialParams.maker = sender;
        initialParams.orderConfig = orderConfig;
        initialParams.virtualXtReserve = 1e8;

        DelegateAble.DelegateParameters memory delegateParams;
        DelegateAble.Signature memory delegateSignature;

        (ITermMaxOrder order, uint256 gtId) = makerHelper.placeOrderForV2(
            res.market,
            salt,
            collateralToMintGt,
            debtTokenToDeposit,
            ftToDeposit,
            xtToDeposit,
            initialParams,
            delegateParams,
            delegateSignature
        );

        assertEq(gtId, order.orderConfig().gtId);
        assertEq(order.maker(), sender);
        assertEq(res.ft.balanceOf(address(order)), ftToDeposit + debtTokenToDeposit);
        assertEq(res.xt.balanceOf(address(order)), xtToDeposit + debtTokenToDeposit);

        vm.stopPrank();
    }

    function testPlaceOrderForV2AndDelegateWithSignature(uint256 salt) public {
        // Set up delegator and delegatee
        uint256 delegatorPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address delegator = vm.addr(delegatorPrivateKey);

        vm.startPrank(delegator);

        uint256 debtTokenToDeposit = 1e8;
        uint128 ftToDeposit = 2e8;
        uint128 xtToDeposit = 0;

        res.debt.mint(delegator, debtTokenToDeposit);
        deal(address(res.ft), delegator, ftToDeposit);
        res.debt.approve(address(makerHelper), debtTokenToDeposit);
        res.ft.approve(address(makerHelper), ftToDeposit);
        res.xt.approve(address(makerHelper), xtToDeposit);
        uint256 collateralToMintGt = 1e18;
        res.collateral.mint(delegator, collateralToMintGt);
        res.collateral.approve(address(makerHelper), collateralToMintGt);

        OrderInitialParams memory initialParams;
        initialParams.maker = delegator;
        initialParams.orderConfig = orderConfig;
        initialParams.virtualXtReserve = 1e8;

        // Set up proper delegation parameters
        uint256 nonce = DelegateAble(address(res.gt)).nonces(delegator);
        uint256 deadline = block.timestamp + 1 hours;
        address delegatee =
            salt % 2 == 0 ? vm.randomAddress() : res.market.predictOrderAddress(initialParams.maker, salt);

        DelegateAble.DelegateParameters memory delegateParams = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: true,
            nonce: nonce,
            deadline: deadline
        });

        // Create valid signature
        bytes32 domainSeparator = DelegateAble(address(res.gt)).DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                delegateParams.delegator,
                delegateParams.delegatee,
                delegateParams.isDelegate,
                delegateParams.nonce,
                delegateParams.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatorPrivateKey, digest);
        DelegateAble.Signature memory delegateSignature = DelegateAble.Signature({v: v, r: r, s: s});

        // Switch to delegatee to call the function (as required by setDelegateWithSignature)
        vm.stopPrank();
        vm.startPrank(delegatee);

        // Also need to approve tokens for delegatee
        res.debt.mint(delegatee, debtTokenToDeposit);
        deal(address(res.ft), delegatee, ftToDeposit);
        res.debt.approve(address(makerHelper), debtTokenToDeposit);
        res.ft.approve(address(makerHelper), ftToDeposit);
        res.xt.approve(address(makerHelper), xtToDeposit);
        res.collateral.mint(delegatee, collateralToMintGt);
        res.collateral.approve(address(makerHelper), collateralToMintGt);
        if (salt % 2 == 0) {
            vm.expectRevert(MakerHelperErrors.OrderAddressIsDifferentFromDelegatee.selector);
        }
        (ITermMaxOrder order, uint256 gtId) = makerHelper.placeOrderForV2(
            res.market,
            salt,
            collateralToMintGt,
            debtTokenToDeposit,
            ftToDeposit,
            xtToDeposit,
            initialParams,
            delegateParams,
            delegateSignature
        );
        if (salt % 2 == 0) return;
        assertEq(gtId, order.orderConfig().gtId);
        assertEq(order.maker(), delegator);
        assertEq(res.ft.balanceOf(address(order)), ftToDeposit + debtTokenToDeposit);
        assertEq(res.xt.balanceOf(address(order)), xtToDeposit + debtTokenToDeposit);

        // Verify delegation was set up correctly
        assertTrue(DelegateAble(address(res.gt)).isDelegate(delegator, delegatee));

        vm.stopPrank();
    }
}
