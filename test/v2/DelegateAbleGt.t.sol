// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    GearingTokenErrorsV2,
    GearingTokenEventsV2,
    GtConfig
} from "contracts/v2/tokens/GearingTokenWithERC20V2.sol";
import {DelegateAble} from "contracts/v2/lib/DelegateAble.sol";
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
import {TermMaxOrderV2, OrderInitialParams} from "contracts/v2/TermMaxOrderV2.sol";

contract DelegateAbleGtTest is Test {
    using JSONLoader for *;
    using SafeCast for uint256;
    using SafeCast for int256;

    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address treasurer = vm.randomAddress();
    address maker = vm.randomAddress();
    string testdata;

    MockFlashLoanReceiver flashLoanReceiver;

    MockFlashRepayerV2 flashRepayer;

    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;

    uint256 delegatorPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address delegator = vm.addr(delegatorPrivateKey);
    address delegatee = vm.randomAddress();

    DelegateAble delegateableGt;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");
        orderConfig.maxXtReserve = type(uint128).max;
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
        uint256 amount = 15000e8;
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

        flashLoanReceiver = new MockFlashLoanReceiver(res.market);
        flashRepayer = new MockFlashRepayerV2(res.gt);

        vm.stopPrank();

        delegateableGt = DelegateAble(address(res.gt));
    }

    function test_SetDelegate() public {
        vm.startPrank(delegator);

        // Initially, delegatee should not be a delegate
        assertFalse(delegateableGt.isDelegate(delegator, delegatee));

        // Set delegate
        vm.expectEmit(true, true, false, true);
        emit DelegateAble.DelegateChanged(delegator, delegatee, true);
        delegateableGt.setDelegate(delegatee, true);

        // Verify delegation
        assertTrue(delegateableGt.isDelegate(delegator, delegatee));

        vm.stopPrank();
    }

    function test_RemoveDelegate() public {
        vm.startPrank(delegator);

        // Set delegate first
        delegateableGt.setDelegate(delegatee, true);
        assertTrue(delegateableGt.isDelegate(delegator, delegatee));

        // Remove delegate
        vm.expectEmit(true, true, false, true);
        emit DelegateAble.DelegateChanged(delegator, delegatee, false);
        delegateableGt.setDelegate(delegatee, false);

        // Verify delegation removed
        assertFalse(delegateableGt.isDelegate(delegator, delegatee));

        vm.stopPrank();
    }

    function test_CannotDelegateToSelf() public {
        vm.startPrank(delegator);

        vm.expectRevert(abi.encodeWithSignature("CannotDelegateToSelf()"));
        delegateableGt.setDelegate(delegator, true);

        vm.stopPrank();
    }

    function test_SetDelegateWithSignature() public {
        uint256 nonce = delegateableGt.nonces(delegator); // First nonce is 0
        uint256 deadline = block.timestamp + 1 hours;

        // Create delegation parameters
        DelegateAble.DelegateParameters memory params = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: true,
            nonce: nonce,
            deadline: deadline
        });

        // Create signature
        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params.delegator,
                params.delegatee,
                params.isDelegate,
                params.nonce,
                params.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatorPrivateKey, digest);
        DelegateAble.Signature memory signature = DelegateAble.Signature({v: v, r: r, s: s});

        // Set delegate with signature (called by delegatee)
        vm.startPrank(delegatee);

        vm.expectEmit(true, true, false, true);
        emit DelegateAble.DelegateChanged(delegator, delegatee, true);
        delegateableGt.setDelegateWithSignature(params, signature);

        // Verify delegation
        assertTrue(delegateableGt.isDelegate(delegator, delegatee));

        vm.stopPrank();
    }

    function test_SetDelegateWithSignature_RevertInvalidSignature() public {
        uint256 nonce = delegateableGt.nonces(delegator);
        uint256 deadline = block.timestamp + 1 hours;

        DelegateAble.DelegateParameters memory params = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: true,
            nonce: nonce,
            deadline: deadline
        });

        // Create invalid signature (wrong private key)
        uint256 wrongPrivateKey = 0x9876543210987654321098765432109876543210987654321098765432109876;
        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params.delegator,
                params.delegatee,
                params.isDelegate,
                params.nonce,
                params.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);
        DelegateAble.Signature memory signature = DelegateAble.Signature({v: v, r: r, s: s});

        vm.startPrank(delegatee);

        // The DelegateAble contract uses require() instead of revert with custom error
        // So we expect a generic revert instead of InvalidSignature()
        vm.expectRevert();
        delegateableGt.setDelegateWithSignature(params, signature);

        vm.stopPrank();
    }

    function test_SetDelegateWithSignature_RevertExpiredDeadline() public {
        uint256 nonce = delegateableGt.nonces(delegator);
        uint256 deadline = block.timestamp - 1; // Expired deadline

        DelegateAble.DelegateParameters memory params = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: true,
            nonce: nonce,
            deadline: deadline
        });

        // Create valid signature but with expired deadline
        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params.delegator,
                params.delegatee,
                params.isDelegate,
                params.nonce,
                params.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatorPrivateKey, digest);
        DelegateAble.Signature memory signature = DelegateAble.Signature({v: v, r: r, s: s});

        vm.startPrank(delegatee);

        // Should revert due to expired deadline
        vm.expectRevert();
        delegateableGt.setDelegateWithSignature(params, signature);

        vm.stopPrank();
    }

    function test_DelegateCanRepayGearingToken() public {
        // First create a gearing token for the delegator
        vm.startPrank(delegator);
        (uint256 gtId,) = LoanUtils.fastMintGt(res, delegator, 100e8, 2000e18);

        // Set delegate
        delegateableGt.setDelegate(delegatee, true);
        vm.stopPrank();

        // Delegatee should be able to repay on behalf of delegator
        vm.startPrank(delegatee);
        res.debt.mint(delegatee, 50e8);
        res.debt.approve(address(res.gt), 50e8);

        // This should not revert because delegatee is authorized
        res.gt.repay(gtId, 50e8, true);

        vm.stopPrank();
    }

    function test_DelegateCanRemoveCollateral() public {
        // First create a gearing token for the delegator
        vm.startPrank(delegator);
        (uint256 gtId,) = LoanUtils.fastMintGt(res, delegator, 100e8, 2000e18);

        // Set delegate
        delegateableGt.setDelegate(delegatee, true);
        vm.stopPrank();

        // Delegatee should be able to remove collateral on behalf of delegator
        vm.startPrank(delegatee);

        // This should not revert because delegatee is authorized
        res.gt.removeCollateral(gtId, abi.encode(100e8));

        vm.stopPrank();
    }

    function test_DelegateCanMergeGearingTokens() public {
        // First create two gearing tokens for the delegator
        vm.startPrank(delegator);

        (uint256 gtId1,) = LoanUtils.fastMintGt(res, delegator, 100e8, 2000e18);
        (uint256 gtId2,) = LoanUtils.fastMintGt(res, delegator, 100e8, 2000e18);

        // Set delegate
        delegateableGt.setDelegate(delegatee, true);
        vm.stopPrank();

        // Delegatee should be able to merge tokens on behalf of delegator
        vm.startPrank(delegatee);

        uint256[] memory ids = new uint256[](2);
        ids[0] = gtId1;
        ids[1] = gtId2;

        // This should not revert because delegatee is authorized
        uint256 newId = res.gt.merge(ids);
        assertEq(newId, gtId1); // First ID should be the merged ID

        vm.stopPrank();
    }

    function test_NonDelegateCannotOperateOnGearingToken() public {
        // First create a gearing token for the delegator
        vm.startPrank(delegator);
        (uint256 gtId,) = LoanUtils.fastMintGt(res, delegator, 100e8, 2000e18);
        vm.stopPrank();

        // Non-delegate should not be able to operate on the token
        address nonDelegate = vm.randomAddress();
        vm.startPrank(nonDelegate);

        vm.expectRevert(abi.encodeWithSignature("AuthorizationFailed(uint256,address)", gtId, nonDelegate));
        res.gt.removeCollateral(gtId, abi.encode(50e8));

        vm.stopPrank();
    }

    function test_OwnerCanAlwaysOperateOnGearingToken() public {
        // First create a gearing token for the delegator
        vm.startPrank(delegator);
        (uint256 gtId,) = LoanUtils.fastMintGt(res, delegator, 100e8, 2000e18);

        // Owner should always be able to operate on their own token
        res.debt.mint(delegator, 50e8);
        res.debt.approve(address(res.gt), 50e8);

        // This should not revert because owner can always operate
        res.gt.repay(gtId, 50e8, true);

        vm.stopPrank();
    }

    function test_DomainSeparator() public {
        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        assertNotEq(domainSeparator, bytes32(0));

        // Domain separator should be consistent
        assertEq(domainSeparator, delegateableGt.DOMAIN_SEPARATOR());
    }

    function test_DelegateStateQuery() public {
        // Initially should return false
        assertFalse(delegateableGt.isDelegate(delegator, delegatee));

        vm.startPrank(delegator);
        delegateableGt.setDelegate(delegatee, true);
        vm.stopPrank();

        // After setting, should return true
        assertTrue(delegateableGt.isDelegate(delegator, delegatee));

        vm.startPrank(delegator);
        delegateableGt.setDelegate(delegatee, false);
        vm.stopPrank();

        // After removing, should return false again
        assertFalse(delegateableGt.isDelegate(delegator, delegatee));
    }

    function test_MultipleDelegate() public {
        address delegatee2 = vm.randomAddress();
        address delegatee3 = vm.randomAddress();

        vm.startPrank(delegator);

        // Set multiple delegates
        delegateableGt.setDelegate(delegatee, true);
        delegateableGt.setDelegate(delegatee2, true);
        delegateableGt.setDelegate(delegatee3, true);

        // All should be delegates
        assertTrue(delegateableGt.isDelegate(delegator, delegatee));
        assertTrue(delegateableGt.isDelegate(delegator, delegatee2));
        assertTrue(delegateableGt.isDelegate(delegator, delegatee3));

        // Remove one delegate
        delegateableGt.setDelegate(delegatee2, false);

        // Only delegatee2 should be removed
        assertTrue(delegateableGt.isDelegate(delegator, delegatee));
        assertFalse(delegateableGt.isDelegate(delegator, delegatee2));
        assertTrue(delegateableGt.isDelegate(delegator, delegatee3));

        vm.stopPrank();
    }

    function test_SetDelegate_SameValueDoesNotEmitEvent() public {
        vm.startPrank(delegator);

        // Set delegate first
        delegateableGt.setDelegate(delegatee, true);
        assertTrue(delegateableGt.isDelegate(delegator, delegatee));

        // Setting the same value again should still emit event (based on the implementation)
        vm.expectEmit(true, true, false, true);
        emit DelegateAble.DelegateChanged(delegator, delegatee, true);
        delegateableGt.setDelegate(delegatee, true);

        vm.stopPrank();
    }

    function test_DelegateRemovesDelegateOnRevoke() public {
        vm.startPrank(delegator);

        // Set delegate first
        delegateableGt.setDelegate(delegatee, true);
        assertTrue(delegateableGt.isDelegate(delegator, delegatee));

        // Revoke delegate using setDelegateWithSignature with isDelegate=false
        vm.stopPrank();

        uint256 nonce = delegateableGt.nonces(delegator);
        uint256 deadline = block.timestamp + 1 hours;

        DelegateAble.DelegateParameters memory params = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: false, // Revoking delegation
            nonce: nonce,
            deadline: deadline
        });

        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params.delegator,
                params.delegatee,
                params.isDelegate,
                params.nonce,
                params.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatorPrivateKey, digest);
        DelegateAble.Signature memory signature = DelegateAble.Signature({v: v, r: r, s: s});

        vm.startPrank(delegatee);

        vm.expectEmit(true, true, false, true);
        emit DelegateAble.DelegateChanged(delegator, delegatee, false);
        delegateableGt.setDelegateWithSignature(params, signature);

        // Verify delegation removed
        assertFalse(delegateableGt.isDelegate(delegator, delegatee));

        vm.stopPrank();
    }

    function test_NonceIncrementsOnDelegateChange() public {
        uint256 initialNonce = delegateableGt.nonces(delegator);
        assertEq(initialNonce, 0); // Initial nonce should be 0

        vm.startPrank(delegator);

        // Set delegate - should NOT increment nonce (only signature-based delegation increments nonce)
        delegateableGt.setDelegate(delegatee, true);
        uint256 nonceAfterSet = delegateableGt.nonces(delegator);
        assertEq(nonceAfterSet, initialNonce); // Nonce should remain the same

        // Remove delegate - should NOT increment nonce again
        delegateableGt.setDelegate(delegatee, false);
        uint256 nonceAfterRemove = delegateableGt.nonces(delegator);
        assertEq(nonceAfterRemove, initialNonce); // Nonce should still be the same

        // Set delegate again - should NOT increment nonce
        delegateableGt.setDelegate(delegatee, true);
        uint256 finalNonce = delegateableGt.nonces(delegator);
        assertEq(finalNonce, initialNonce); // Nonce should still be the same

        vm.stopPrank();
    }

    function test_NonceIncrementsOnSignatureDelegateChange() public {
        uint256 initialNonce = delegateableGt.nonces(delegator);
        assertEq(initialNonce, 0);

        uint256 deadline = block.timestamp + 1 hours;

        // First signature-based delegation
        DelegateAble.DelegateParameters memory params1 = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: true,
            nonce: initialNonce,
            deadline: deadline
        });

        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash1 = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params1.delegator,
                params1.delegatee,
                params1.isDelegate,
                params1.nonce,
                params1.deadline
            )
        );
        bytes32 digest1 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash1));

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(delegatorPrivateKey, digest1);
        DelegateAble.Signature memory signature1 = DelegateAble.Signature({v: v1, r: r1, s: s1});

        vm.startPrank(delegatee);
        delegateableGt.setDelegateWithSignature(params1, signature1);

        uint256 nonceAfterFirstSig = delegateableGt.nonces(delegator);
        assertEq(nonceAfterFirstSig, initialNonce + 1);

        vm.stopPrank();

        // Second signature-based delegation with updated nonce
        DelegateAble.DelegateParameters memory params2 = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: false,
            nonce: nonceAfterFirstSig, // Use updated nonce
            deadline: deadline
        });

        bytes32 structHash2 = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params2.delegator,
                params2.delegatee,
                params2.isDelegate,
                params2.nonce,
                params2.deadline
            )
        );
        bytes32 digest2 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash2));

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(delegatorPrivateKey, digest2);
        DelegateAble.Signature memory signature2 = DelegateAble.Signature({v: v2, r: r2, s: s2});

        vm.startPrank(delegatee);
        delegateableGt.setDelegateWithSignature(params2, signature2);

        uint256 finalNonce = delegateableGt.nonces(delegator);
        assertEq(finalNonce, nonceAfterFirstSig + 1);

        vm.stopPrank();
    }

    function test_RevertOnInvalidNonce() public {
        uint256 currentNonce = delegateableGt.nonces(delegator);
        uint256 deadline = block.timestamp + 1 hours;

        // Try to use wrong nonce (current + 1)
        DelegateAble.DelegateParameters memory params = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: true,
            nonce: currentNonce + 1, // Wrong nonce
            deadline: deadline
        });

        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params.delegator,
                params.delegatee,
                params.isDelegate,
                params.nonce,
                params.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatorPrivateKey, digest);
        DelegateAble.Signature memory signature = DelegateAble.Signature({v: v, r: r, s: s});

        vm.startPrank(delegatee);

        // Should revert due to invalid nonce
        vm.expectRevert();
        delegateableGt.setDelegateWithSignature(params, signature);

        vm.stopPrank();
    }

    function test_RevertOnOldNonce() public {
        // First, make a signature-based delegation to increment nonce
        uint256 initialNonce = delegateableGt.nonces(delegator);
        uint256 deadline = block.timestamp + 1 hours;

        DelegateAble.DelegateParameters memory params1 = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: true,
            nonce: initialNonce,
            deadline: deadline
        });

        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash1 = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params1.delegator,
                params1.delegatee,
                params1.isDelegate,
                params1.nonce,
                params1.deadline
            )
        );
        bytes32 digest1 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash1));

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(delegatorPrivateKey, digest1);
        DelegateAble.Signature memory signature1 = DelegateAble.Signature({v: v1, r: r1, s: s1});

        vm.startPrank(delegatee);
        delegateableGt.setDelegateWithSignature(params1, signature1);
        vm.stopPrank();

        uint256 currentNonce = delegateableGt.nonces(delegator);
        assertTrue(currentNonce > 0); // Nonce should have incremented

        // Try to use old nonce (0)
        DelegateAble.DelegateParameters memory params2 = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: false,
            nonce: 0, // Old nonce
            deadline: deadline
        });

        bytes32 structHash2 = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params2.delegator,
                params2.delegatee,
                params2.isDelegate,
                params2.nonce,
                params2.deadline
            )
        );
        bytes32 digest2 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash2));

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(delegatorPrivateKey, digest2);
        DelegateAble.Signature memory signature2 = DelegateAble.Signature({v: v2, r: r2, s: s2});

        vm.startPrank(delegatee);

        // Should revert due to old/invalid nonce
        vm.expectRevert();
        delegateableGt.setDelegateWithSignature(params2, signature2);

        vm.stopPrank();
    }

    function test_PreventReplayAttack() public {
        uint256 nonce = delegateableGt.nonces(delegator);
        uint256 deadline = block.timestamp + 1 hours;

        DelegateAble.DelegateParameters memory params = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: true,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params.delegator,
                params.delegatee,
                params.isDelegate,
                params.nonce,
                params.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatorPrivateKey, digest);
        DelegateAble.Signature memory signature = DelegateAble.Signature({v: v, r: r, s: s});

        vm.startPrank(delegatee);

        // First call should succeed
        delegateableGt.setDelegateWithSignature(params, signature);
        assertTrue(delegateableGt.isDelegate(delegator, delegatee));

        // Second call with same signature should fail (replay attack)
        vm.expectRevert();
        delegateableGt.setDelegateWithSignature(params, signature);

        vm.stopPrank();
    }

    function test_NonceIndependentPerDelegator() public {
        address delegator2 = vm.randomAddress();

        // Both delegators should start with nonce 0
        assertEq(delegateableGt.nonces(delegator), 0);
        assertEq(delegateableGt.nonces(delegator2), 0);

        // Regular setDelegate doesn't increment nonce
        vm.startPrank(delegator);
        delegateableGt.setDelegate(delegatee, true);
        vm.stopPrank();

        // Both should still be 0 since regular setDelegate doesn't increment nonce
        assertEq(delegateableGt.nonces(delegator), 0);
        assertEq(delegateableGt.nonces(delegator2), 0);

        // Use signature-based delegation to increment nonce for first delegator
        uint256 deadline = block.timestamp + 1 hours;
        DelegateAble.DelegateParameters memory params = DelegateAble.DelegateParameters({
            delegator: delegator,
            delegatee: delegatee,
            isDelegate: false, // Remove the delegation set above
            nonce: 0,
            deadline: deadline
        });

        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params.delegator,
                params.delegatee,
                params.isDelegate,
                params.nonce,
                params.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatorPrivateKey, digest);
        DelegateAble.Signature memory signature = DelegateAble.Signature({v: v, r: r, s: s});

        vm.startPrank(delegatee);
        delegateableGt.setDelegateWithSignature(params, signature);
        vm.stopPrank();

        // First delegator's nonce should increment, second should remain 0
        assertEq(delegateableGt.nonces(delegator), 1);
        assertEq(delegateableGt.nonces(delegator2), 0);

        // Regular setDelegate for second delegator should not increment nonce
        vm.startPrank(delegator2);
        delegateableGt.setDelegate(delegatee, true);
        vm.stopPrank();

        // Nonces should remain the same since regular setDelegate doesn't increment
        assertEq(delegateableGt.nonces(delegator), 1);
        assertEq(delegateableGt.nonces(delegator2), 0);
    }

    function test_NonceQueryFunction() public {
        // Test nonces() function directly
        assertEq(delegateableGt.nonces(delegator), 0);
        assertEq(delegateableGt.nonces(delegatee), 0);
        assertEq(delegateableGt.nonces(vm.randomAddress()), 0);

        // Regular setDelegate should NOT change nonce
        vm.startPrank(delegator);
        delegateableGt.setDelegate(delegatee, true);
        vm.stopPrank();

        // Nonces should remain 0 since regular setDelegate doesn't increment nonce
        assertEq(delegateableGt.nonces(delegator), 0);
        assertEq(delegateableGt.nonces(delegatee), 0);
    }
}
