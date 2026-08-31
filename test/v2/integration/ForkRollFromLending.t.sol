// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {MarketConfig, OrderConfig} from "contracts/v1/storage/TermMaxStorage.sol";
import {OrderInitialParams} from "contracts/v2/storage/TermMaxStorageV2.sol";
import {TermMaxOrderV2} from "contracts/v2/TermMaxOrderV2.sol";
import {SwapUnit} from "contracts/v1/router/ISwapAdapter.sol";
import {SwapPath} from "contracts/v2/router/ITermMaxRouterV2.sol";
import {TermMaxRouterV2_02, FlashCallbackKind} from "contracts/v2/router/TermMaxRouterV2_02.sol";
import {FlashLoanProvider} from "contracts/v2/router/ITermMaxRouterV2_02.sol";
import {RouterErrorsV2} from "contracts/v2/errors/RouterErrorsV2.sol";
import {TermMaxSwapAdapter, TermMaxSwapData} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
import {IAaveV3Pool} from "contracts/v2/extensions/aave/IAaveV3Pool.sol";
import {IMorpho, Id, MarketParams, Authorization, Signature} from "contracts/v2/extensions/morpho/IMorpho.sol";
import {IWhitelistManager} from "contracts/v2/access/IWhitelistManager.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {DeployUtils} from "test/v2/utils/DeployUtils.sol";
import {JSONLoader} from "test/v2/utils/JSONLoader.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";

/// @dev Morpho's supply side, which the test uses to make sure the real market it borrows from has
///      liquidity regardless of that market's utilisation at the fork block.
interface IMorphoTestExt {
    function supply(MarketParams memory marketParams, uint256 assets, uint256 shares, address onBehalf, bytes memory d)
        external
        returns (uint256, uint256);
}

/// @dev Aave's price oracle, quoting USD with 8 decimals. The test seeds the TermMax market's price
///      feeds from it, so the fixed rate position is valued the way aave values the same assets.
interface IAaveOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

/// @dev One rollover call, kept in a struct so each test can tweak a single field. The router
///      itself takes these flat, with `rolloverData` packed by the caller.
struct RollCase {
    FlashLoanProvider protocol;
    address lendingPool;
    bytes positionData;
    uint256 flashAmt;
    uint256 collateralAmt;
    IERC20 additionalAsset;
    uint256 additionalAmt;
    uint128 maxDebtAmt;
    SwapPath swapFtPath;
    bytes delegationData;
}

/// @notice Fork test for `TermMaxRouterV2_02.rolloverFromLendingProtocol`: rolling a floating rate
///         wstETH/USDC borrow position on REAL Aave V3 and a REAL Morpho Blue market into a
///         TermMax fixed rate position, funded by a flash loan from that same protocol.
///         Everything on the third party side is the mainnet deployment — the Aave wstETH and USDC
///         reserves, and the wstETH/USDC morpho market curated by the Steakhouse USDC vault with
///         its production oracle, 86% lltv and AdaptiveCurve IRM. The TermMax market and order are
///         deployed on the fork (no wstETH/USDC market exists on mainnet) but priced from aave's
///         own oracle. So every external call the router makes — reserve and position reads,
///         repay-on-behalf, aToken permit and pull, withdrawCollateral on behalf, the share
///         accounting of a full repayment — runs against production bytecode and production state.
contract ForkRollFromLending is Test {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 constant FORK_BLOCK = 22985670; // 2025-07-24

    address wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IAaveV3Pool aave = IAaveV3Pool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    IAaveOracle aaveOracle = IAaveOracle(0x54586bE62E3c3580375aE3723C145253060Ca0C2);
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    /// @dev A REAL morpho market: wstETH collateral against USDC, 86% lltv, the AdaptiveCurve IRM
    ///      and a production ChainlinkOracle, curated by the Steakhouse USDC MetaMorpho vault
    Id morphoMarketId = Id.wrap(0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc);
    /// @dev Another real market, WBTC against USDC, to prove the token pair is checked
    Id wrongMorphoMarketId = Id.wrap(0x3a85e619751152991742810df6ec69ce473daef99e28a64ab2340d7b7ccfee49);

    MarketParams morphoMarket;

    DeployUtils.Res res;
    TermMaxRouterV2_02 router02;
    address tmxAdapter;
    address aWstEth;
    address usdcVariableDebt;

    uint256 userPk = 0xA11CE;
    address user;
    address attacker = makeAddr("attacker");
    address admin = makeAddr("admin");

    /// @dev the rolled position: 1 wstETH of collateral backing 1000 USDC of floating rate debt
    uint256 constant COLLATERAL = 1e18;
    uint256 constant DEBT = 1000e6;
    /// @dev the new fixed rate position is issued with 30% of headroom over the rolled debt,
    ///      the ft that is not needed to repay the flash loan repays the excess right away
    uint256 constant DEBT_HEADROOM_BPS = 13000;

    string testdata;

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, FORK_BLOCK);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));
        user = vm.addr(userPk);

        aWstEth = aave.getReserveData(wstEth).aTokenAddress;
        usdcVariableDebt = aave.getReserveData(usdc).variableDebtTokenAddress;

        _deployTermMax();
        _loadMorphoMarket();

        vm.label(address(aave), "aavePool");
        vm.label(address(morpho), "morpho");
        vm.label(aWstEth, "aWstETH");
        vm.label(usdcVariableDebt, "variableDebtUSDC");
        vm.label(wstEth, "wstETH");
        vm.label(address(aaveOracle), "aaveOracle");
        vm.label(usdc, "USDC");
        vm.label(address(router02), "router02");
        vm.label(address(res.router), "routerV2");
        vm.label(address(res.market), "termMaxMarket");
        vm.label(address(res.order), "termMaxOrder");
        vm.label(user, "user");
    }

    // ------------------------------------------------------------------
    // Aave -> TermMax
    // ------------------------------------------------------------------

    function testRollFromAaveFull() public {
        _openAavePosition(user, COLLATERAL, DEBT);
        _approveAToken();

        uint256 newGtId = _roll(_aaveCase(DEBT, type(uint256).max));

        // the whole aave position is gone
        assertEq(IERC20(usdcVariableDebt).balanceOf(user), 0, "aave debt should be fully repaid");
        assertEq(IERC20(aWstEth).balanceOf(user), 0, "aave collateral should be fully withdrawn");
        _assertNewPosition(newGtId, COLLATERAL, DEBT);
        _assertRoutersEmpty();
    }

    function testRollFromAavePartial() public {
        _openAavePosition(user, COLLATERAL, DEBT);
        _approveAToken();

        uint256 debtBefore = IERC20(usdcVariableDebt).balanceOf(user);
        uint256 newGtId = _roll(_aaveCase(DEBT / 2, COLLATERAL / 2));

        // half of the position stays on aave, and stays healthy
        assertApproxEqAbs(IERC20(usdcVariableDebt).balanceOf(user), debtBefore - DEBT / 2, 1e3, "half the debt stays");
        assertApproxEqAbs(IERC20(aWstEth).balanceOf(user), COLLATERAL / 2, 1e12, "half the collateral stays");
        _assertNewPosition(newGtId, COLLATERAL / 2, DEBT / 2);
        _assertRoutersEmpty();
    }

    /// @dev Aave aTokens are EIP-2612 permittable, so the allowance the router needs can be
    ///      handed over inside the rollover transaction instead of in a separate approve.
    function testRollFromAaveWithATokenPermit() public {
        _openAavePosition(user, COLLATERAL, DEBT);

        RollCase memory params = _aaveCase(DEBT, type(uint256).max);
        params.delegationData = _aTokenPermit(COLLATERAL);

        assertEq(IERC20(aWstEth).allowance(user, address(router02)), 0, "no allowance upfront");
        uint256 newGtId = _roll(params);

        assertEq(IERC20(usdcVariableDebt).balanceOf(user), 0, "aave debt should be fully repaid");
        assertEq(IERC20(aWstEth).balanceOf(user), 0, "aave collateral should be fully withdrawn");
        _assertNewPosition(newGtId, COLLATERAL, DEBT);
        _assertRoutersEmpty();
    }

    /// @dev The caller tops the new position up with extra collateral, lowering its ltv.
    function testRollFromAaveWithAdditionalCollateral() public {
        _openAavePosition(user, COLLATERAL, DEBT);
        _approveAToken();

        uint256 extraCollateral = 0.5e18;
        deal(wstEth, user, extraCollateral);
        vm.prank(user);
        IERC20(wstEth).approve(address(router02), extraCollateral);

        RollCase memory params = _aaveCase(DEBT, type(uint256).max);
        params.additionalAsset = IERC20(wstEth);
        params.additionalAmt = extraCollateral;
        uint256 newGtId = _roll(params);

        _assertNewPosition(newGtId, COLLATERAL + extraCollateral, DEBT);
        assertEq(IERC20(wstEth).balanceOf(user), 0, "the additional collateral is fully used");
        _assertRoutersEmpty();
    }

    /// @dev The caller pays the rollover cost in debt token instead of borrowing it, so the new
    ///      fixed rate debt ends up smaller than the debt that was rolled.
    function testRollFromAaveWithAdditionalDebtToken() public {
        _openAavePosition(user, COLLATERAL, DEBT);
        _approveAToken();

        uint256 buffer = 100e6;
        deal(usdc, user, IERC20(usdc).balanceOf(user) + buffer);
        vm.prank(user);
        IERC20(usdc).approve(address(router02), buffer);

        RollCase memory params = _aaveCase(DEBT, type(uint256).max);
        params.additionalAsset = IERC20(usdc);
        params.additionalAmt = buffer;
        uint256 newGtId = _roll(params);

        (, uint128 newDebt,) = _newGt().loanInfo(newGtId);
        assertLt(newDebt, DEBT, "the buffer should push the new debt below the rolled debt");
        _assertRoutersEmpty();
    }

    /// @dev The frontend does not have to know the debt to the wei: it can flash borrow more than
    ///      the position owes, and the part the repayment does not consume pays the loan back.
    function testRollFromAaveWithPaddedFlashLoan() public {
        _openAavePosition(user, COLLATERAL, DEBT);
        _approveAToken();

        uint256 padding = 100e6;
        RollCase memory params = _aaveCase(DEBT + padding, type(uint256).max);
        uint256 newGtId = _roll(params);

        assertEq(IERC20(usdcVariableDebt).balanceOf(user), 0, "aave debt should be fully repaid");
        assertEq(IERC20(aWstEth).balanceOf(user), 0, "aave collateral should be fully withdrawn");
        _assertNewPosition(newGtId, COLLATERAL, DEBT);
        _assertRoutersEmpty();
    }

    /// @dev A debt token buffer worth the whole new position is not a rollover: repaying that much
    ///      would burn the fresh gt and hand the collateral back, and keeping the remainder here
    ///      would strand it, so the amounts are rejected instead.
    function testDebtTokenSurplusAboveTheNewDebtReverts() public {
        _openAavePosition(user, COLLATERAL, DEBT);
        _approveAToken();

        uint256 buffer = 2000e6;
        deal(usdc, user, IERC20(usdc).balanceOf(user) + buffer);
        vm.prank(user);
        IERC20(usdc).approve(address(router02), buffer);

        RollCase memory params = _aaveCase(DEBT, type(uint256).max);
        params.additionalAsset = IERC20(usdc);
        params.additionalAmt = buffer;

        vm.prank(user);
        vm.expectPartialRevert(RouterErrorsV2.SurplusExceedsNewDebt.selector);
        _call(params);
    }

    /// @dev When the caller holds none of the new market's collateral in the third party protocol,
    ///      the collateral leg is skipped entirely — no zero amount ever reaches aave's aToken
    ///      transfer or its withdraw, both of which reject zero. Here the caller's aave debt is
    ///      backed by WETH and they roll it onto TermMax against wstETH they bring themselves,
    ///      leaving the WETH where it is.
    function testRollFromAaveWithoutMovingCollateral() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address aWeth = aave.getReserveData(weth).aTokenAddress;
        deal(weth, user, 1e18);
        vm.startPrank(user);
        IERC20(weth).approve(address(aave), 1e18);
        aave.supply(weth, 1e18, user, 0);
        aave.borrow(usdc, DEBT, 2, 0, user);
        vm.stopPrank();

        assertEq(IERC20(aWstEth).balanceOf(user), 0, "no wstETH supplied to aave");

        // the collateral of the new position comes from the caller, not out of aave
        deal(wstEth, user, COLLATERAL);
        vm.startPrank(user);
        IERC20(wstEth).approve(address(router02), COLLATERAL);
        IERC20(aWstEth).approve(address(router02), type(uint256).max);
        vm.stopPrank();

        RollCase memory params = _aaveCase(DEBT, type(uint256).max);
        params.additionalAsset = IERC20(wstEth);
        params.additionalAmt = COLLATERAL;
        uint256 newGtId = _roll(params);

        assertEq(IERC20(usdcVariableDebt).balanceOf(user), 0, "the aave debt is repaid");
        assertApproxEqAbs(IERC20(aWeth).balanceOf(user), 1e18, 1e12, "the aave collateral is untouched");
        _assertNewPosition(newGtId, COLLATERAL, DEBT);
        _assertRoutersEmpty();
    }

    // ------------------------------------------------------------------
    // Morpho -> TermMax
    // ------------------------------------------------------------------

    function testRollFromMorphoFull() public {
        _openMorphoPosition(user, COLLATERAL, DEBT);
        vm.prank(user);
        morpho.setAuthorization(address(router02), true);

        uint256 newGtId = _roll(_morphoCase(_morphoDebtAssets(user), type(uint256).max));

        (, uint128 borrowShares, uint128 collateral) = morpho.position(morphoMarketId, user);
        assertEq(borrowShares, 0, "every borrow share should be burnt");
        assertEq(collateral, 0, "all morpho collateral should be withdrawn");
        _assertNewPosition(newGtId, COLLATERAL, DEBT);
        _assertRoutersEmpty();
    }

    function testRollFromMorphoPartial() public {
        _openMorphoPosition(user, COLLATERAL, DEBT);
        vm.prank(user);
        morpho.setAuthorization(address(router02), true);

        (, uint128 sharesBefore,) = morpho.position(morphoMarketId, user);
        uint256 newGtId = _roll(_morphoCase(DEBT / 2, COLLATERAL / 2));

        (, uint128 borrowShares, uint128 collateral) = morpho.position(morphoMarketId, user);
        assertGt(borrowShares, 0, "half the debt stays on morpho");
        assertApproxEqRel(uint256(borrowShares), uint256(sharesBefore) / 2, 0.01e18, "about half the shares stay");
        assertEq(collateral, COLLATERAL / 2, "half the collateral stays on morpho");
        _assertNewPosition(newGtId, COLLATERAL / 2, DEBT / 2);
        _assertRoutersEmpty();
    }

    /// @dev A full rollover after interest has accrued: the debt is priced from the borrow
    ///      shares, so the position closes without leaving dust debt behind — dust debt with no
    ///      collateral left would make the withdrawal revert.
    function testRollFromMorphoAfterInterestAccrual() public {
        _openMorphoPosition(user, COLLATERAL, DEBT);
        vm.prank(user);
        morpho.setAuthorization(address(router02), true);

        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);

        /// @dev The debt has grown past DEBT and nothing is read before the loan is taken, so the
        /// caller pads it: burning every borrow share costs whatever the position owes by now,
        /// and an under-sized loan simply reverts. The unused padding pays the loan back.
        uint256 newGtId = _roll(_morphoCase(_morphoDebtAssets(user), type(uint256).max));

        (, uint128 borrowShares, uint128 collateral) = morpho.position(morphoMarketId, user);
        assertEq(borrowShares, 0, "every borrow share should be burnt");
        assertEq(collateral, 0, "all morpho collateral should be withdrawn");
        (, uint128 newDebt,) = _newGt().loanInfo(newGtId);
        assertGt(newDebt, DEBT, "the rolled debt should include the accrued interest");
    }

    /// @dev Closing a morpho position costs a wei more than what was borrowed, because borrowing
    ///      rounds the borrow shares up. A loan sized at the borrowed amount is therefore short,
    ///      and the rollover does not quietly roll less than asked: the share of debt it would
    ///      leave behind makes taking out all of the collateral unhealthy, so morpho reverts.
    function testUnderfundedMorphoCloseReverts() public {
        _openMorphoPosition(user, COLLATERAL, DEBT);
        vm.prank(user);
        morpho.setAuthorization(address(router02), true);

        assertGt(_morphoDebtAssets(user), DEBT, "closing costs more than what was borrowed");
        RollCase memory params = _morphoCase(DEBT, type(uint256).max);
        vm.prank(user);
        vm.expectRevert(bytes("insufficient collateral"));
        _call(params);

        (, uint128 borrowShares, uint128 collateral) = morpho.position(morphoMarketId, user);
        assertGt(borrowShares, 0, "the position is untouched");
        assertEq(collateral, COLLATERAL, "the position is untouched");
    }

    /// @dev The morpho authorization can also be handed over inside the rollover transaction.
    function testRollFromMorphoWithAuthorizationSig() public {
        _openMorphoPosition(user, COLLATERAL, DEBT);

        RollCase memory params = _morphoCase(_morphoDebtAssets(user), type(uint256).max);
        params.delegationData = _morphoAuthorization(userPk, user, address(router02));

        assertFalse(morpho.isAuthorized(user, address(router02)), "not authorized upfront");
        uint256 newGtId = _roll(params);

        (, uint128 borrowShares, uint128 collateral) = morpho.position(morphoMarketId, user);
        assertEq(borrowShares, 0, "every borrow share should be burnt");
        assertEq(collateral, 0, "all morpho collateral should be withdrawn");
        _assertNewPosition(newGtId, COLLATERAL, DEBT);
        _assertRoutersEmpty();
    }

    // ------------------------------------------------------------------
    // Security
    // ------------------------------------------------------------------

    /// @dev The point of resolving the position from `_msgSender()`: an aToken allowance granted
    ///      to the router is only ever usable by the account that granted it.
    function testCannotRollSomeoneElsesAavePosition() public {
        _openAavePosition(user, COLLATERAL, DEBT);
        _approveAToken();

        // the attacker has no aave position of their own, so there is nothing to roll — and no
        // parameter that could point the flow at the victim
        RollCase memory params = _aaveCase(DEBT, type(uint256).max);
        vm.prank(attacker);
        // the protocol itself rejects repaying a debt the caller does not have
        vm.expectRevert();
        _call(params);

        assertGt(IERC20(usdcVariableDebt).balanceOf(user), 0, "victim still owes its debt");
        assertApproxEqAbs(IERC20(aWstEth).balanceOf(user), COLLATERAL, 1e12, "victim keeps its collateral");
    }

    /// @dev Same for a morpho authorization: it is only ever used for the caller's own position.
    function testCannotRollSomeoneElsesMorphoPosition() public {
        _openMorphoPosition(user, COLLATERAL, DEBT);
        vm.prank(user);
        morpho.setAuthorization(address(router02), true);

        RollCase memory params = _morphoCase(DEBT, type(uint256).max);
        vm.prank(attacker);
        // the protocol itself rejects repaying a debt the caller does not have
        vm.expectRevert();
        _call(params);

        (, uint128 borrowShares, uint128 collateral) = morpho.position(morphoMarketId, user);
        assertGt(borrowShares, 0, "victim still owes its debt");
        assertEq(collateral, COLLATERAL, "victim keeps its collateral");
    }

    /// @dev A hostile lending pool DOES get to call the callback with a payload of its own, but
    ///      the account the flow acts for lives in transient storage, not in that payload. Here
    ///      the pool forges the collateral amount to the victim's, and the pull still targets the
    ///      attacker who opened the flow — the victim's standing aToken allowance is unreachable.
    function testHostilePoolCannotRedirectToAnotherUser() public {
        // the victim holds a position and a standing aToken allowance for the router
        _openAavePosition(user, COLLATERAL, DEBT);
        _approveAToken();

        // the attacker rolls a position of their own, through a pool they control
        _openAavePosition(attacker, 0.1e18, 50e6);
        vm.startPrank(attacker);
        IERC20(aWstEth).approve(address(router02), type(uint256).max);
        vm.stopPrank();

        HostilePool pool = new HostilePool(router02, aave);
        // the forged payload asks for the victim's collateral instead of the attacker's
        pool.setForgedCollateralAmt(COLLATERAL);
        deal(usdc, address(pool), DEBT * 2);

        RollCase memory params = _aaveCase(DEBT, type(uint256).max);
        params.lendingPool = address(pool);

        vm.prank(attacker);
        // the forged amount is resolved inside the callback against the ATTACKER's own aToken
        // balance, which is 10x smaller, so it is rejected outright
        vm.expectRevert(
            abi.encodeWithSelector(RouterErrorsV2.CollateralAmtExceedsPosition.selector, 0.1e18, COLLATERAL)
        );
        _call(params);

        // the victim is untouched
        assertGt(IERC20(usdcVariableDebt).balanceOf(user), 0, "victim still owes its debt");
        assertApproxEqAbs(IERC20(aWstEth).balanceOf(user), COLLATERAL, 1e12, "victim keeps its collateral");
    }

    function testCallbackFromUnknownSenderReverts() public {
        vm.prank(attacker);
        vm.expectRevert(RouterErrorsV2.CallbackAddressNotMatch.selector);
        router02.onMorphoFlashLoan(1, "");

        vm.prank(attacker);
        vm.expectRevert(RouterErrorsV2.CallbackAddressNotMatch.selector);
        router02.executeOperation(usdc, 1, 0, address(router02), "");
    }

    function testFtSaleMustPayTheRouterBack() public {
        _openAavePosition(user, COLLATERAL, DEBT);
        _approveAToken();
        RollCase memory params = _aaveCase(DEBT, type(uint256).max);
        params.swapFtPath.recipient = attacker;

        vm.prank(user);
        vm.expectRevert(RouterErrorsV2.InvalidSwapRecipient.selector);
        _call(params);
    }

    function testCollateralAmtAboveThePositionReverts() public {
        _openMorphoPosition(user, COLLATERAL, DEBT);
        vm.prank(user);
        morpho.setAuthorization(address(router02), true);

        RollCase memory params = _morphoCase(DEBT, COLLATERAL + 1);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(RouterErrorsV2.CollateralAmtExceedsPosition.selector, COLLATERAL, COLLATERAL + 1)
        );
        _call(params);

        (, uint128 borrowShares, uint128 collateral) = morpho.position(morphoMarketId, user);
        assertGt(borrowShares, 0, "the position is untouched");
        assertEq(collateral, COLLATERAL, "the position is untouched");
    }

    function testMorphoMarketMustMatchTheNewMarketTokens() public {
        _openMorphoPosition(user, COLLATERAL, DEBT);
        RollCase memory params = _morphoCase(DEBT, type(uint256).max);
        params.positionData = abi.encode(Id.wrap(0xbc552f0b14dd6f8e60b760a534ac1d8613d3539153b4d9675d697e048f2edc7e));

        vm.prank(user);
        vm.expectRevert(RouterErrorsV2.LendingMarketTokensNotMatch.selector);
        _call(params);
    }

    function testAdditionalAssetMustBelongToTheNewMarket() public {
        _openAavePosition(user, COLLATERAL, DEBT);
        RollCase memory params = _aaveCase(DEBT, type(uint256).max);
        params.additionalAsset = IERC20(address(res.ft));
        params.additionalAmt = 1;

        vm.prank(user);
        vm.expectRevert(RouterErrorsV2.InvalidAdditionalAsset.selector);
        _call(params);
    }

    // ------------------------------------------------------------------
    // Helpers: rolling
    // ------------------------------------------------------------------

    function _roll(RollCase memory params) internal returns (uint256 newGtId) {
        vm.prank(user);
        newGtId = _call(params);
    }

    /// @dev `rolloverData` is packed by the caller and unpacked inside the flash loan callback
    function _call(RollCase memory params) internal returns (uint256 newGtId) {
        newGtId = router02.rolloverFromLendingProtocol(
            ITermMaxMarket(address(res.market)),
            params.flashAmt,
            params.collateralAmt,
            params.additionalAsset,
            params.additionalAmt,
            params.protocol,
            params.lendingPool,
            params.positionData,
            params.delegationData,
            abi.encode(address(res.router), params.maxDebtAmt, params.swapFtPath)
        );
    }

    function _approveAToken() internal {
        vm.prank(user);
        IERC20(aWstEth).approve(address(router02), type(uint256).max);
    }

    function _aaveCase(uint256 flashAmt, uint256 collateralAmt) internal view returns (RollCase memory params) {
        params = _baseCase(flashAmt);
        params.protocol = FlashLoanProvider.AAVE;
        params.lendingPool = address(aave);
        params.collateralAmt = collateralAmt;
    }

    function _morphoCase(uint256 flashAmt, uint256 collateralAmt) internal view returns (RollCase memory params) {
        params = _baseCase(flashAmt);
        params.protocol = FlashLoanProvider.MORPHO;
        params.lendingPool = address(morpho);
        params.positionData = abi.encode(morphoMarketId);
        params.collateralAmt = collateralAmt;
    }

    /// @dev The flash loan IS the repayment budget, so `flashAmt` is what gets rolled. The sale
    ///      target is not quoted here at all: the router overwrites it with the exact shortfall.
    function _baseCase(uint256 flashAmt) internal view returns (RollCase memory params) {
        uint128 maxDebtAmt = uint128(flashAmt * DEBT_HEADROOM_BPS / 10000);
        params.flashAmt = flashAmt;
        params.maxDebtAmt = maxDebtAmt;
        params.swapFtPath = _ftSellPath(maxDebtAmt, flashAmt);
    }

    /// @dev The ft sell path, quoted by the caller as before: it has to cover the flash loan plus
    ///      its fee, and quoting 0.1% above the loan covers aave's 5bps premium without the test
    ///      having to know it — whatever the repayment does not need repays the new position.
    function _ftSellPath(uint128 maxDebtAmt, uint256 flashAmt) internal view returns (SwapPath memory path) {
        uint128 expectedFtOut = maxDebtAmt - uint128(uint256(maxDebtAmt) * res.market.mintGtFeeRatio() / 1e8);
        address[] memory orders = new address[](1);
        orders[0] = address(res.order);
        uint128[] memory tradingAmts = new uint128[](1);
        tradingAmts[0] = uint128(flashAmt + flashAmt / 1000);
        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: false,
            scalingFactor: 0,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: expectedFtOut,
            deadline: block.timestamp + 1,
            refundAddress: address(res.router)
        });
        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] =
            SwapUnit({adapter: tmxAdapter, tokenIn: address(res.ft), tokenOut: usdc, swapData: abi.encode(swapData)});
        path =
            SwapPath({inputAmount: expectedFtOut, recipient: address(router02), useBalanceOnchain: true, units: units});
    }

    // ------------------------------------------------------------------
    // Helpers: delegation signatures
    // ------------------------------------------------------------------

    function _aTokenPermit(uint256 value) internal view returns (bytes memory) {
        bytes32 permitTypehash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(permitTypehash, user, address(router02), value, IERC20Permit(aWstEth).nonces(user), deadline)
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", IERC20Permit(aWstEth).DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);
        return abi.encode(value, deadline, v, r, s);
    }

    function _morphoAuthorization(uint256 pk, address authorizer, address authorized)
        internal
        view
        returns (bytes memory)
    {
        Authorization memory auth = Authorization({
            authorizer: authorizer,
            authorized: authorized,
            isAuthorized: true,
            nonce: morpho.nonce(authorizer),
            deadline: block.timestamp + 1 hours
        });
        bytes32 typehash = keccak256(
            "Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(typehash, auth.authorizer, auth.authorized, auth.isAuthorized, auth.nonce, auth.deadline)
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", morpho.DOMAIN_SEPARATOR(), structHash));
        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(pk, digest);
        return abi.encode(auth, sig);
    }

    // ------------------------------------------------------------------
    // Helpers: assertions
    // ------------------------------------------------------------------

    function _newGt() internal view returns (IGearingToken gt) {
        (,, gt,,) = res.market.tokens();
    }

    function _assertNewPosition(uint256 newGtId, uint256 expectedCollateral, uint256 rolledDebt) internal view {
        IGearingToken gt = _newGt();
        (address owner, uint128 debt, bytes memory collData) = gt.loanInfo(newGtId);
        assertEq(owner, user, "the caller should own the new gt");
        assertEq(IERC721(address(gt)).ownerOf(newGtId), user, "the caller should own the new gt");
        assertApproxEqAbs(abi.decode(collData, (uint256)), expectedCollateral, 1e12, "new collateral");
        assertGe(debt, rolledDebt, "the new debt covers the rolled debt");
        assertLe(debt, rolledDebt * DEBT_HEADROOM_BPS / 10000, "the new debt stays within the issued debt");
        console.log("rolled debt", rolledDebt);
        console.log("new fixed rate debt", debt);
    }

    function _assertRoutersEmpty() internal view {
        assertEq(IERC20(usdc).balanceOf(address(router02)), 0, "router02 holds no debt token");
        assertEq(IERC20(wstEth).balanceOf(address(router02)), 0, "router02 holds no collateral");
        assertEq(IERC20(aWstEth).balanceOf(address(router02)), 0, "router02 holds no aToken");
        assertEq(res.ft.balanceOf(address(res.router)), 0, "routerV2 holds no ft");
        assertEq(IERC20(usdc).balanceOf(address(res.router)), 0, "routerV2 holds no debt token");
        assertEq(IERC20(wstEth).balanceOf(address(res.router)), 0, "routerV2 holds no collateral");
        assertEq(IERC20(usdc).allowance(address(router02), address(morpho)), 0, "no morpho allowance survives");
        assertEq(IERC20(usdc).allowance(address(router02), address(aave)), 0, "no aave allowance survives");
    }

    // ------------------------------------------------------------------
    // Helpers: third party positions
    // ------------------------------------------------------------------

    function _openAavePosition(address who, uint256 collateral, uint256 debt) internal {
        deal(wstEth, who, collateral);
        vm.startPrank(who);
        IERC20(wstEth).approve(address(aave), collateral);
        aave.supply(wstEth, collateral, who, 0);
        aave.borrow(usdc, debt, 2, 0, who);
        vm.stopPrank();
        assertEq(IERC20(usdc).balanceOf(who), debt, "the borrowed usdc lands with the borrower");
    }

    function _openMorphoPosition(address who, uint256 collateral, uint256 debt) internal {
        deal(wstEth, who, collateral);
        vm.startPrank(who);
        IERC20(wstEth).approve(address(morpho), collateral);
        morpho.supplyCollateral(morphoMarket, collateral, who, "");
        morpho.borrow(morphoMarket, debt, 0, who, who);
        vm.stopPrank();
        assertEq(IERC20(usdc).balanceOf(who), debt, "the borrowed usdc lands with the borrower");
    }

    // ------------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------------

    function _setPrice(MockPriceFeed feed, uint256 answer) internal {
        feed.updateRoundData(
            MockPriceFeed.RoundData({
                roundId: 1,
                answer: int256(answer),
                startedAt: block.timestamp,
                updatedAt: block.timestamp,
                answeredInRound: 1
            })
        );
    }

    /// @dev What closing `who`'s morpho position costs right now: the same SharesMathLib.toAssetsUp
    ///      conversion morpho charges for burning every borrow share. It is always at least a wei
    ///      above the amount that was borrowed, because borrowing rounds the shares up — this is
    ///      the number a frontend has to size a full rollover's flash loan with.
    function _morphoDebtAssets(address who) internal returns (uint256) {
        morpho.accrueInterest(morphoMarket);
        (, uint128 borrowShares,) = morpho.position(morphoMarketId, who);
        (,, uint128 totalBorrowAssets, uint128 totalBorrowShares,,) = morpho.market(morphoMarketId);
        return
            Math.mulDiv(
                borrowShares, uint256(totalBorrowAssets) + 1, uint256(totalBorrowShares) + 1e6, Math.Rounding.Ceil
            );
    }

    function _loadMorphoMarket() internal {
        morphoMarket = morpho.idToMarketParams(morphoMarketId);
        assertEq(morphoMarket.loanToken, usdc, "the real morpho market lends USDC");
        assertEq(morphoMarket.collateralToken, wstEth, "the real morpho market takes wstETH");

        // make sure the market has the liquidity the position borrows, whatever its utilisation
        // happens to be at this block
        address lender = makeAddr("morphoLender");
        uint256 liquidity = 1_000_000e6;
        deal(usdc, lender, liquidity);
        vm.startPrank(lender);
        IERC20(usdc).approve(address(morpho), liquidity);
        IMorphoTestExt(address(morpho)).supply(morphoMarket, liquidity, 0, lender, "");
        vm.stopPrank();
    }

    function _deployTermMax() internal {
        MarketConfig memory marketConfig = JSONLoader.getMarketConfigFromJson(admin, testdata, ".marketConfig");
        marketConfig.maturity = uint64(block.timestamp + 90 days);
        OrderConfig memory orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        vm.startPrank(admin);
        res = DeployUtils.deployMarket(admin, marketConfig, 0.89e8, 0.9e8, wstEth, usdc);
        /// @dev Both feeds report 8 decimals and are seeded from aave's own oracle, so the ltv
        /// the TermMax gt computes is the one aave and morpho worked with at this block.
        _setPrice(res.collateralOracle, aaveOracle.getAssetPrice(wstEth));
        _setPrice(res.debtOracle, aaveOracle.getAssetPrice(usdc));

        // an order deep enough to absorb the ft the rollover sells
        OrderInitialParams memory orderParams;
        orderParams.maker = admin;
        orderParams.orderConfig = orderConfig;
        orderParams.virtualXtReserve = 15_000e6;
        res.order = TermMaxOrderV2(address(res.market.createOrder(orderParams)));

        uint256 liquidity = 50_000e6;
        deal(usdc, admin, liquidity);
        IERC20(usdc).approve(address(res.market), liquidity);
        res.market.mint(admin, liquidity);
        res.ft.transfer(address(res.order), liquidity);
        res.xt.transfer(address(res.order), liquidity);

        // the main router the extension delegates the issue-and-sell flow to, the extension
        // under test, and the swap adapter the ft sale goes through
        res.router = DeployUtils.deployRouter(admin, address(res.whitelistManager));
        TermMaxRouterV2_02 impl = new TermMaxRouterV2_02(address(res.whitelistManager));
        router02 = TermMaxRouterV2_02(
            address(new ERC1967Proxy(address(impl), abi.encodeCall(TermMaxRouterV2_02.initialize, (admin))))
        );
        tmxAdapter = address(new TermMaxSwapAdapter(address(res.whitelistManager)));
        address[] memory adapters = new address[](1);
        adapters[0] = tmxAdapter;
        res.whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);
        vm.stopPrank();
    }
}

/// @dev A pool that reports the real reserves — so the router resolves a real position and takes
///      the flash loan from it — but then funds the loan and calls the callback with a payload of
///      its own instead of the one the router handed it.
contract HostilePool {
    TermMaxRouterV2_02 public immutable router;
    IAaveV3Pool public immutable realPool;
    uint256 public forgedCollateralAmt;

    constructor(TermMaxRouterV2_02 router_, IAaveV3Pool realPool_) {
        router = router_;
        realPool = realPool_;
    }

    function setForgedCollateralAmt(uint256 amt) external {
        forgedCollateralAmt = amt;
    }

    function getReserveData(address asset) external view returns (IAaveV3Pool.ReserveData memory) {
        return realPool.getReserveData(asset);
    }

    /// @dev No-ops, so the flow gets all the way to the forged collateral pull
    function repay(address, uint256 amount, uint256, address) external pure returns (uint256) {
        return amount;
    }

    function withdraw(address, uint256, address) external pure returns (uint256) {
        return 0;
    }

    function flashLoanSimple(address receiver, address asset, uint256 amount, bytes calldata params, uint16) external {
        IERC20(asset).transfer(receiver, amount);
        TermMaxRouterV2_02(receiver).executeOperation(asset, amount, 0, receiver, _forge(params));
    }

    /// @dev Re-encode the payload with the collateral amount swapped for the victim's
    function _forge(bytes calldata params) internal view returns (bytes memory) {
        (FlashCallbackKind kind, bytes memory payload) = abi.decode(params, (FlashCallbackKind, bytes));
        (
            FlashLoanProvider protocol,
            bytes memory positionData,,
            ITermMaxMarket newMarket,
            IGearingToken newGt,
            address collateral,
            IERC20 debtToken,
            bytes memory delegationData,
            bytes memory rolloverData
        ) = abi.decode(
            payload, (FlashLoanProvider, bytes, uint256, ITermMaxMarket, IGearingToken, address, IERC20, bytes, bytes)
        );
        return abi.encode(
            kind,
            abi.encode(
                protocol,
                positionData,
                forgedCollateralAmt,
                newMarket,
                newGt,
                collateral,
                debtToken,
                delegationData,
                rolloverData
            )
        );
    }
}
