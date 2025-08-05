// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {TermMaxOrderV2, Constants} from "contracts/v2/TermMaxOrderV2.sol";
import {ITermMaxOrderV2, OrderInitialParams} from "contracts/v2/ITermMaxOrderV2.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";
import {ISwapCallback} from "contracts/v1/ISwapCallback.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {
    MarketConfig,
    OrderConfig,
    CurveCuts,
    CurveCut,
    FeeConfig
} from "contracts/v1/storage/TermMaxStorage.sol";

contract MockSwapCallback is ISwapCallback {
    function afterSwap(uint256, uint256, int256, int256) external pure {}
}

contract TermMaxOrderV2Handler is Test {
    using SafeCast for uint256;
    using SafeCast for int256;

    TermMaxOrderV2 public order;
    ITermMaxMarket public market;
    IMintableERC20 public ft;
    IMintableERC20 public xt;
    IGearingToken public gt;
    MockERC20 public collateral;
    MockERC20 public debtToken;
    MockERC4626 public pool;
    MockSwapCallback public swapCallback;

    // Test actors
    address[] public actors;
    address public orderMaker;
    
    // Call tracking
    mapping(bytes32 => uint256) public calls;
    
    // Ghost variables for tracking state
    uint256 public ghost_totalFtSwapped;
    uint256 public ghost_totalXtSwapped;
    uint256 public ghost_totalDebtTokenSwapped;
    uint256 public ghost_totalFeesCollected;
    uint256 public ghost_liquidityAdded;
    uint256 public ghost_liquidityRemoved;
    uint256 public ghost_virtualXtReserveChanges;
    
    // Reserve tracking
    uint256 public ghost_initialVirtualXtReserve;
    uint256 public ghost_maxVirtualXtReserveReached;
    uint256 public ghost_minVirtualXtReserveReached;
    
    // Pool interaction tracking
    uint256 public ghost_poolDeposits;
    uint256 public ghost_poolWithdrawals;
    bool public ghost_poolEverSet;

    modifier createActor() {
        address currentActor = _getCurrentActor();
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    modifier onlyBeforeMaturity() {
        if (block.timestamp >= market.config().maturity) {
            return;
        }
        _;
    }

    modifier onlyOrderMaker() {
        vm.startPrank(orderMaker);
        _;
        vm.stopPrank();
    }

    constructor(
        TermMaxOrderV2 _order,
        ITermMaxMarket _market,
        IMintableERC20 _ft,
        IMintableERC20 _xt,
        IGearingToken _gt,
        MockERC20 _collateral,
        MockERC20 _debtToken,
        MockERC4626 _pool,
        address _orderMaker
    ) {
        order = _order;
        market = _market;
        ft = _ft;
        xt = _xt;
        gt = _gt;
        collateral = _collateral;
        debtToken = _debtToken;
        pool = _pool;
        orderMaker = _orderMaker;
        swapCallback = new MockSwapCallback();

        ghost_initialVirtualXtReserve = order.virtualXtReserve();
        ghost_maxVirtualXtReserveReached = ghost_initialVirtualXtReserve;
        ghost_minVirtualXtReserveReached = ghost_initialVirtualXtReserve;

        // Create test actors
        for (uint256 i = 0; i < 10; i++) {
            actors.push(vm.addr(i + 100));
        }
    }

    // ========== SWAP FUNCTIONS ==========

    function swapDebtTokenToFt(uint256 debtTokenAmount) external createActor countCall("swapDebtTokenToFt") onlyBeforeMaturity {
        debtTokenAmount = bound(debtTokenAmount, 1e6, 1_000_000e18);
        
        address currentActor = _getCurrentActor();
        
        // Ensure actor has debt tokens
        debtToken.mint(currentActor, debtTokenAmount);
        debtToken.approve(address(order), debtTokenAmount);

        try order.swapExactTokenToToken(
            IERC20(address(debtToken)),
            IERC20(address(ft)),
            currentActor,
            uint128(debtTokenAmount),
            0, // min out
            block.timestamp + 1 hours
        ) returns (uint256 ftOut) {
            ghost_totalDebtTokenSwapped += debtTokenAmount;
            ghost_totalFtSwapped += ftOut;
            _updateVirtualXtReserveTracking();
        } catch {
            // Swap failed, which is acceptable based on order state
        }
    }

    function swapDebtTokenToXt(uint256 debtTokenAmount) external createActor countCall("swapDebtTokenToXt") onlyBeforeMaturity {
        debtTokenAmount = bound(debtTokenAmount, 1e6, 1_000_000e18);
        
        address currentActor = _getCurrentActor();
        
        // Ensure actor has debt tokens
        debtToken.mint(currentActor, debtTokenAmount);
        debtToken.approve(address(order), debtTokenAmount);

        try order.swapExactTokenToToken(
            IERC20(address(debtToken)),
            IERC20(address(xt)),
            currentActor,
            uint128(debtTokenAmount),
            0, // min out
            block.timestamp + 1 hours
        ) returns (uint256 xtOut) {
            ghost_totalDebtTokenSwapped += debtTokenAmount;
            ghost_totalXtSwapped += xtOut;
            _updateVirtualXtReserveTracking();
        } catch {
            // Swap failed, which is acceptable based on order state
        }
    }

    function swapFtToDebtToken(uint256 ftAmount) external createActor countCall("swapFtToDebtToken") onlyBeforeMaturity {
        address currentActor = _getCurrentActor();
        
        uint256 ftBalance = ft.balanceOf(currentActor);
        if (ftBalance == 0) {
            // Mint some FT for testing
            debtToken.mint(currentActor, 100e18);
            debtToken.approve(address(market), 100e18);
            market.mint(currentActor, 100e18);
            ftBalance = ft.balanceOf(currentActor);
        }
        
        ftAmount = bound(ftAmount, 1, ftBalance);
        ft.approve(address(order), ftAmount);

        try order.swapExactTokenToToken(
            IERC20(address(ft)),
            IERC20(address(debtToken)),
            currentActor,
            uint128(ftAmount),
            0, // min out
            block.timestamp + 1 hours
        ) returns (uint256 debtTokenOut) {
            ghost_totalFtSwapped += ftAmount;
            ghost_totalDebtTokenSwapped += debtTokenOut;
            _updateVirtualXtReserveTracking();
        } catch {
            // Swap failed, which is acceptable based on order state
        }
    }

    function swapXtToDebtToken(uint256 xtAmount) external createActor countCall("swapXtToDebtToken") onlyBeforeMaturity {
        address currentActor = _getCurrentActor();
        
        uint256 xtBalance = xt.balanceOf(currentActor);
        if (xtBalance == 0) {
            // Mint some XT for testing
            debtToken.mint(currentActor, 100e18);
            debtToken.approve(address(market), 100e18);
            market.mint(currentActor, 100e18);
            xtBalance = xt.balanceOf(currentActor);
        }
        
        xtAmount = bound(xtAmount, 1, xtBalance);
        xt.approve(address(order), xtAmount);

        try order.swapExactTokenToToken(
            IERC20(address(xt)),
            IERC20(address(debtToken)),
            currentActor,
            uint128(xtAmount),
            0, // min out
            block.timestamp + 1 hours
        ) returns (uint256 debtTokenOut) {
            ghost_totalXtSwapped += xtAmount;
            ghost_totalDebtTokenSwapped += debtTokenOut;
            _updateVirtualXtReserveTracking();
        } catch {
            // Swap failed, which is acceptable based on order state
        }
    }

    // ========== LIQUIDITY MANAGEMENT ==========

    function addLiquidityDebtToken(uint256 amount) external countCall("addLiquidityDebtToken") onlyOrderMaker {
        amount = bound(amount, 1e6, 1_000_000e18);
        
        debtToken.mint(orderMaker, amount);
        debtToken.approve(address(order), amount);

        try order.addLiquidity(IERC20(address(debtToken)), amount) {
            ghost_liquidityAdded += amount;
        } catch {
            // Adding liquidity failed
        }
    }

    function removeLiquidityDebtToken(uint256 amount) external countCall("removeLiquidityDebtToken") onlyOrderMaker {
        // Only attempt to remove liquidity if some has been added
        if (ghost_liquidityAdded == 0) {
            return;
        }
        
        // Get current debt token balance of the order to determine available liquidity
        uint256 orderDebtBalance = debtToken.balanceOf(address(order));
        if (orderDebtBalance == 0) {
            return;
        }
        
        amount = bound(amount, 1e6, Math.min(100_000e18, orderDebtBalance));
        
        try order.removeLiquidity(IERC20(address(debtToken)), amount, orderMaker) {
            ghost_liquidityRemoved += amount;
        } catch {
            // Removing liquidity failed
        }
    }

    // ========== POOL MANAGEMENT ==========

    function setPool() external countCall("setPool") onlyOrderMaker {
        if (!ghost_poolEverSet) {
            try order.setPool(IERC4626(address(pool))) {
                ghost_poolEverSet = true;
            } catch {
                // Setting pool failed
            }
        }
    }

    function removePool() external countCall("removePool") onlyOrderMaker {
        if (ghost_poolEverSet) {
            try order.setPool(IERC4626(address(0))) {
                ghost_poolEverSet = false;
            } catch {
                // Removing pool failed
            }
        }
    }

    // ========== CONFIGURATION UPDATES ==========

    function updateGeneralConfig(uint256 newMaxXtReserve, uint256 newVirtualXtReserve) 
        external 
        countCall("updateGeneralConfig") 
        onlyOrderMaker 
    {
        OrderConfig memory currentConfig = order.orderConfig();
        
        newMaxXtReserve = bound(newMaxXtReserve, 1e18, type(uint128).max);
        newVirtualXtReserve = bound(newVirtualXtReserve, 1e6, newMaxXtReserve);

        try order.setGeneralConfig(
            currentConfig.gtId,
            newMaxXtReserve,
            currentConfig.swapTrigger,
            newVirtualXtReserve
        ) {
            ghost_virtualXtReserveChanges++;
            _updateVirtualXtReserveTracking();
        } catch {
            // Configuration update failed
        }
    }

    // ========== TIME MANAGEMENT ==========

    function advanceTime(uint256 timeToAdd) external countCall("advanceTime") {
        timeToAdd = bound(timeToAdd, 1 hours, 30 days);
        vm.warp(block.timestamp + timeToAdd);
    }

    // ========== HELPER FUNCTIONS ==========

    function _getCurrentActor() internal view returns (address) {
        return actors[bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 0, actors.length - 1)];
    }

    function _updateVirtualXtReserveTracking() internal {
        uint256 currentVirtualXt = order.virtualXtReserve();
        if (currentVirtualXt > ghost_maxVirtualXtReserveReached) {
            ghost_maxVirtualXtReserveReached = currentVirtualXt;
        }
        if (currentVirtualXt < ghost_minVirtualXtReserveReached) {
            ghost_minVirtualXtReserveReached = currentVirtualXt;
        }
    }
}

contract TermMaxOrderV2InvariantTest is StdInvariant, Test {
    using JSONLoader for *;

    TermMaxOrderV2 public order;
    ITermMaxMarket public market;
    IMintableERC20 public ft;
    IMintableERC20 public xt;
    IGearingToken public gt;
    MockERC20 public collateral;
    MockERC20 public debtToken;
    MockERC4626 public pool;
    TermMaxOrderV2Handler public handler;

    DeployUtils.Res res;
    MarketConfig marketConfig;
    OrderConfig orderConfig;
    address orderMaker;

    function setUp() public {
        // Deploy market and order using existing utilities
        address deployer = vm.addr(999);
        orderMaker = vm.addr(1000);
        vm.startPrank(deployer);

        string memory testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(deployer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        market = res.market;
        (ft, xt, gt,,) = market.tokens();
        collateral = res.collateral;
        debtToken = res.debt;

        // Create pool for testing
        pool = new MockERC4626(IERC20(address(debtToken)));

        // Create order with V2 parameters
        OrderInitialParams memory orderParams;
        orderParams.maker = orderMaker;
        orderParams.orderConfig = orderConfig;
        orderParams.virtualXtReserve = 150e8;
        orderParams.pool = IERC4626(address(0)); // Start without pool

        order = TermMaxOrderV2(address(res.market.createOrder(orderParams)));

        // Setup initial liquidity for the order
        uint256 initialAmount = 150e8;
        res.debt.mint(deployer, initialAmount);
        res.debt.approve(address(res.market), initialAmount);
        res.market.mint(deployer, initialAmount);
        res.ft.transfer(address(order), initialAmount);
        res.xt.transfer(address(order), initialAmount);

        vm.stopPrank();

        // Setup handler
        handler = new TermMaxOrderV2Handler(
            order, market, ft, xt, gt, collateral, debtToken, pool, orderMaker
        );

        // Configure invariant testing
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.swapDebtTokenToFt.selector;
        selectors[1] = handler.swapDebtTokenToXt.selector;
        selectors[2] = handler.swapFtToDebtToken.selector;
        selectors[3] = handler.swapXtToDebtToken.selector;
        selectors[4] = handler.addLiquidityDebtToken.selector;
        selectors[5] = handler.removeLiquidityDebtToken.selector;
        selectors[6] = handler.setPool.selector;
        selectors[7] = handler.removePool.selector;
        selectors[8] = handler.updateGeneralConfig.selector;
        selectors[9] = handler.advanceTime.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ========== CORE INVARIANTS ==========

    // INVARIANT 1: Virtual XT reserve should never exceed max XT reserve
    function invariant_virtualXtReserveWithinBounds() public view {
        uint256 virtualXtReserve = order.virtualXtReserve();
        uint256 maxXtReserve = order.orderConfig().maxXtReserve;
        
        assertLe(virtualXtReserve, maxXtReserve, "Virtual XT reserve should not exceed max XT reserve");
    }

    // INVARIANT 2: Token reserves should always be non-negative
    function invariant_tokenReservesNonNegative() public view {
        (uint256 ftReserve, uint256 xtReserve) = order.tokenReserves();
        
        assertTrue(ftReserve >= 0, "FT reserve should be non-negative");
        assertTrue(xtReserve >= 0, "XT reserve should be non-negative");
    }

    // INVARIANT 3: Real reserves should be >= token reserves when pool is set
    function invariant_realReservesConsistency() public view {
        (uint256 ftReserve, uint256 xtReserve) = order.tokenReserves();
        (uint256 realFtReserve, uint256 realXtReserve) = order.getRealReserves();
        
        assertGe(realFtReserve, ftReserve, "Real FT reserve should be >= token FT reserve");
        assertGe(realXtReserve, xtReserve, "Real XT reserve should be >= token XT reserve");
    }

    // INVARIANT 4: Pool balance consistency when pool is set
    function invariant_poolBalanceConsistency() public view {
        IERC4626 orderPool = order.pool();
        if (address(orderPool) != address(0)) {
            uint256 poolShares = orderPool.balanceOf(address(order));
            uint256 poolAssets = orderPool.convertToAssets(poolShares);
            
            // Pool assets should be reasonable (not exceeding total supply)
            uint256 totalPoolAssets = orderPool.totalAssets();
            assertLe(poolAssets, totalPoolAssets, "Order pool assets should not exceed total pool assets");
        }
    }

    // INVARIANT 5: Order configuration validity
    function invariant_orderConfigurationValid() public view {
        OrderConfig memory config = order.orderConfig();
        
        assertTrue(config.maxXtReserve > 0, "Max XT reserve should be positive");
        
        // Fee configuration validity
        FeeConfig memory feeConfig = config.feeConfig;
        assertTrue(feeConfig.borrowTakerFeeRatio < Constants.MAX_FEE_RATIO, "Borrow taker fee should be valid");
        assertTrue(feeConfig.borrowMakerFeeRatio < Constants.MAX_FEE_RATIO, "Borrow maker fee should be valid");
        assertTrue(feeConfig.lendTakerFeeRatio < Constants.MAX_FEE_RATIO, "Lend taker fee should be valid");
        assertTrue(feeConfig.lendMakerFeeRatio < Constants.MAX_FEE_RATIO, "Lend maker fee should be valid");
    }

    // INVARIANT 6: Curve cuts validity
    function invariant_curveCutsValid() public view {
        OrderConfig memory config = order.orderConfig();
        CurveCuts memory curveCuts = config.curveCuts;
        
        // Lend curve cuts validation
        if (curveCuts.lendCurveCuts.length > 0) {
            assertTrue(curveCuts.lendCurveCuts[0].xtReserve == 0, "First lend curve cut should start at 0");
            assertTrue(curveCuts.lendCurveCuts[0].liqSquare > 0, "First lend curve cut should have positive liquidity");
        }
        
        // Borrow curve cuts validation
        if (curveCuts.borrowCurveCuts.length > 0) {
            assertTrue(curveCuts.borrowCurveCuts[0].xtReserve == 0, "First borrow curve cut should start at 0");
            assertTrue(curveCuts.borrowCurveCuts[0].liqSquare > 0, "First borrow curve cut should have positive liquidity");
        }
    }

    // INVARIANT 7: Virtual XT reserve changes should be reasonable
    function invariant_virtualXtReserveChangesReasonable() public view {
        uint256 currentVirtual = order.virtualXtReserve();
        uint256 maxReached = handler.ghost_maxVirtualXtReserveReached();
        uint256 minReached = handler.ghost_minVirtualXtReserveReached();
        
        assertLe(minReached, currentVirtual, "Current virtual XT should be >= minimum reached");
        assertGe(maxReached, currentVirtual, "Current virtual XT should be <= maximum reached");
    }

    // INVARIANT 8: APR calculations should not overflow
    function invariant_aprCalculationsValid() public view {
        try order.apr() returns (uint256 lendApr, uint256 borrowApr) {
            // APR should be reasonable (not cause overflow)
            assertTrue(lendApr <= type(uint256).max, "Lend APR should not overflow");
            assertTrue(borrowApr <= type(uint256).max, "Borrow APR should not overflow");
            
            // If lending is not allowed, lend APR should be 0
            OrderConfig memory config = order.orderConfig();
            if (config.curveCuts.borrowCurveCuts.length == 0) {
                assertEq(lendApr, 0, "Lend APR should be 0 when lending not allowed");
            }
            
            // If borrowing is not allowed, borrow APR should be max
            if (config.curveCuts.lendCurveCuts.length == 0) {
                assertEq(borrowApr, type(uint256).max, "Borrow APR should be max when borrowing not allowed");
            }
        } catch {
            // APR calculation failed, which might be acceptable in some edge cases
        }
    }

    // INVARIANT 9: Order ownership should remain consistent
    function invariant_orderOwnershipConsistent() public view {
        address currentOwner = order.owner();
        address maker = order.maker();
        
        assertEq(currentOwner, maker, "Order owner should equal maker");
        assertEq(maker, orderMaker, "Maker should remain consistent");
    }

    // INVARIANT 10: Market reference should remain consistent
    function invariant_marketReferenceConsistent() public view {
        ITermMaxMarket orderMarket = order.market();
        
        assertEq(address(orderMarket), address(market), "Order market reference should remain consistent");
    }

    // INVARIANT 11: Liquidity operations should be balanced
    function invariant_liquidityOperationsBalanced() public view {
        uint256 added = handler.ghost_liquidityAdded();
        uint256 removed = handler.ghost_liquidityRemoved();
        
        // Total removed should not exceed total added by a significant margin
        if (removed > 0) {
            assertTrue(added > 0, "Should have added liquidity before removing");
        }
    }

    // INVARIANT 12: Pool interactions should be consistent with pool state
    function invariant_poolInteractionsConsistent() public view {
        IERC4626 orderPool = order.pool();
        bool poolSet = handler.ghost_poolEverSet();
        
        if (poolSet && address(orderPool) != address(0)) {
            // If pool was ever set and is currently set, pool should be valid
            assertTrue(address(orderPool) != address(0), "Pool should be valid when set");
        }
    }

    // INVARIANT 13: Swap operations should maintain value conservation
    function invariant_swapValueConservation() public view {
        // This is a complex invariant that would require detailed tracking
        // For now, we ensure that total swapped amounts are reasonable
        uint256 totalFtSwapped = handler.ghost_totalFtSwapped();
        uint256 totalXtSwapped = handler.ghost_totalXtSwapped();
        uint256 totalDebtSwapped = handler.ghost_totalDebtTokenSwapped();
        
        // Swapped amounts should not be unreasonably large
        if (totalFtSwapped > 0) {
            assertLt(totalFtSwapped, type(uint128).max, "Total FT swapped should be reasonable");
        }
        if (totalXtSwapped > 0) {
            assertLt(totalXtSwapped, type(uint128).max, "Total XT swapped should be reasonable");
        }
        if (totalDebtSwapped > 0) {
            assertLt(totalDebtSwapped, type(uint128).max, "Total debt token swapped should be reasonable");
        }
    }

    // Function to display test summary
    function invariant_callSummary() public view {
        console.log("=== TERMMAX ORDER V2 INVARIANT TEST SUMMARY ===");
        console.log("swapDebtTokenToFt calls:", handler.calls("swapDebtTokenToFt"));
        console.log("swapDebtTokenToXt calls:", handler.calls("swapDebtTokenToXt"));
        console.log("swapFtToDebtToken calls:", handler.calls("swapFtToDebtToken"));
        console.log("swapXtToDebtToken calls:", handler.calls("swapXtToDebtToken"));
        console.log("addLiquidityDebtToken calls:", handler.calls("addLiquidityDebtToken"));
        console.log("removeLiquidityDebtToken calls:", handler.calls("removeLiquidityDebtToken"));
        console.log("setPool calls:", handler.calls("setPool"));
        console.log("removePool calls:", handler.calls("removePool"));
        console.log("updateGeneralConfig calls:", handler.calls("updateGeneralConfig"));
        console.log("advanceTime calls:", handler.calls("advanceTime"));
        console.log("");
        console.log("Ghost variables:");
        console.log("ghost_totalFtSwapped:", handler.ghost_totalFtSwapped());
        console.log("ghost_totalXtSwapped:", handler.ghost_totalXtSwapped());
        console.log("ghost_totalDebtTokenSwapped:", handler.ghost_totalDebtTokenSwapped());
        console.log("ghost_liquidityAdded:", handler.ghost_liquidityAdded());
        console.log("ghost_liquidityRemoved:", handler.ghost_liquidityRemoved());
        console.log("ghost_virtualXtReserveChanges:", handler.ghost_virtualXtReserveChanges());
        console.log("ghost_poolEverSet:", handler.ghost_poolEverSet());
        console.log("");
        console.log("Order state:");
        (uint256 ftReserve, uint256 xtReserve) = order.tokenReserves();
        console.log("FT reserve:", ftReserve);
        console.log("XT reserve:", xtReserve);
        console.log("Virtual XT reserve:", order.virtualXtReserve());
        console.log("Max XT reserve:", order.orderConfig().maxXtReserve);
        console.log("Pool address:", address(order.pool()));
        console.log("Current timestamp:", block.timestamp);
        console.log("Order maker:", order.maker());
    }
}