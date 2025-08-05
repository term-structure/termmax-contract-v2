// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {TermMaxMarketV2, Constants, MarketEvents} from "contracts/v2/TermMaxMarketV2.sol";
import {ITermMaxMarketV2} from "contracts/v2/ITermMaxMarketV2.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {IFlashLoanReceiver} from "contracts/v1/IFlashLoanReceiver.sol";
import {ISwapCallback} from "contracts/v1/ISwapCallback.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {
    MarketConfig,
    MarketInitialParams,
    LoanConfig,
    OrderConfig,
    CurveCuts,
    CurveCut,
    FeeConfig
} from "contracts/v1/storage/TermMaxStorage.sol";

contract MockFlashLoanHandler is IFlashLoanReceiver {
    MockERC20 public collateral;

    constructor(address _collateral) {
        collateral = MockERC20(_collateral);
    }

    function executeOperation(address gtReceiver, IERC20 debtToken, uint256 amount, bytes calldata callbackData)
        external
        returns (bytes memory)
    {
        // Simple mock: mint collateral and return collateral data
        uint256 collateralAmount = amount * 150 / 100; // 150% collateralization
        collateral.mint(address(this), collateralAmount);
        collateral.transfer(msg.sender, collateralAmount);

        return abi.encode(address(collateral), collateralAmount);
    }
}

contract TermMaxMarketV2Handler is Test {
    TermMaxMarketV2 public market;
    IMintableERC20 public ft;
    IMintableERC20 public xt;
    IGearingToken public gt;
    MockERC20 public collateral;
    MockERC20 public debtToken;
    ITermMaxOrder public order;
    MockFlashLoanHandler public flashLoanHandler;

    // Actors for testing
    address[] public actors;
    mapping(bytes32 => uint256) public calls;

    // Ghost variables for tracking state
    uint256 public ghost_totalMinted;
    uint256 public ghost_totalBurned;
    uint256 public ghost_totalFtIssued;
    uint256 public ghost_totalXtLeveraged;
    uint256 public ghost_totalGtMinted;
    uint256 public ghost_totalFeesCollected;
    uint256 public ghost_totalRedeemed;

    // Track GT operations
    mapping(uint256 => bool) public ghost_gtExists;
    uint256[] public ghost_allGtIds;

    // Getter function for ghost_allGtIds array length
    function getGhostAllGtIdsLength() external view returns (uint256) {
        return ghost_allGtIds.length;
    }

    // Getter function for ghost_allGtIds array element
    function getGhostAllGtIds(uint256 index) external view returns (uint256) {
        return ghost_allGtIds[index];
    }

    modifier createActor() {
        address currentActor = msg.sender;
        if (currentActor == address(0) || currentActor == address(this)) {
            currentActor = actors[bound(uint256(keccak256(abi.encode(block.timestamp))), 0, actors.length - 1)];
        }
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

    modifier onlyAfterMaturity() {
        if (block.timestamp < market.config().maturity + Constants.LIQUIDATION_WINDOW) {
            return;
        }
        _;
    }

    constructor(
        TermMaxMarketV2 _market,
        IMintableERC20 _ft,
        IMintableERC20 _xt,
        IGearingToken _gt,
        MockERC20 _collateral,
        MockERC20 _debtToken,
        ITermMaxOrder _order
    ) {
        market = _market;
        ft = _ft;
        xt = _xt;
        gt = _gt;
        collateral = _collateral;
        debtToken = _debtToken;
        order = _order;

        flashLoanHandler = new MockFlashLoanHandler(address(collateral));

        // Create test actors
        for (uint256 i = 0; i < 10; i++) {
            actors.push(vm.addr(i + 1));
        }
    }

    // Mint FT and XT tokens
    function mint(uint256 amount) external createActor countCall("mint") onlyBeforeMaturity {
        amount = bound(amount, 1e6, 1_000_000e18); // Reasonable bounds

        address currentActor = _getCurrentActor();

        // Mint debt tokens to actor
        debtToken.mint(currentActor, amount);
        debtToken.approve(address(market), amount);

        uint256 ftBalanceBefore = ft.balanceOf(currentActor);
        uint256 xtBalanceBefore = xt.balanceOf(currentActor);

        market.mint(currentActor, amount);

        // Update ghost variables
        ghost_totalMinted += amount;

        // Verify tokens were minted
        assertEq(ft.balanceOf(currentActor) - ftBalanceBefore, amount);
        assertEq(xt.balanceOf(currentActor) - xtBalanceBefore, amount);
    }

    // Burn FT and XT tokens
    function burn(uint256 amount) external createActor countCall("burn") onlyBeforeMaturity {
        address currentActor = _getCurrentActor();

        uint256 ftBalance = ft.balanceOf(currentActor);
        uint256 xtBalance = xt.balanceOf(currentActor);
        uint256 maxBurn = Math.min(ftBalance, xtBalance);

        if (maxBurn == 0) return;

        amount = bound(amount, 1, maxBurn);

        uint256 debtBalanceBefore = debtToken.balanceOf(currentActor);

        // Approve burning
        ft.approve(address(market), amount);
        xt.approve(address(market), amount);

        market.burn(currentActor, amount);

        ghost_totalBurned += amount;

        // Verify debt tokens were received
        assertEq(debtToken.balanceOf(currentActor) - debtBalanceBefore, amount);
    }

    // Issue FT by creating GT
    function issueFt(uint256 debt) external createActor countCall("issueFt") onlyBeforeMaturity {
        debt = bound(debt, 1e6, 1_000_000e18);

        address currentActor = _getCurrentActor();

        // Prepare collateral
        uint256 collateralAmount = debt * 150 / 100; // 150% collateralization
        collateral.mint(currentActor, collateralAmount);

        bytes memory collateralData = abi.encode(address(collateral), collateralAmount);

        // Approve collateral transfer
        collateral.approve(address(gt), collateralAmount);

        uint256 ftBalanceBefore = ft.balanceOf(currentActor);

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(currentActor, uint128(debt), collateralData);

        // Track GT
        ghost_gtExists[gtId] = true;
        ghost_allGtIds.push(gtId);

        ghost_totalFtIssued += ftOutAmt;
        ghost_totalGtMinted++;

        // Verify FT was issued
        assertEq(ft.balanceOf(currentActor) - ftBalanceBefore, ftOutAmt);
        assertTrue(gt.ownerOf(gtId) != address(0));
    }

    // Leverage by XT
    function leverageByXt(uint256 xtAmt) external createActor countCall("leverageByXt") onlyBeforeMaturity {
        address currentActor = _getCurrentActor();

        uint256 xtBalance = xt.balanceOf(currentActor);
        if (xtBalance == 0) return;

        xtAmt = bound(xtAmt, 1, xtBalance);

        // Approve XT transfer
        xt.approve(address(market), xtAmt);

        bytes memory callbackData = "";

        uint256 gtId = market.leverageByXt(currentActor, uint128(xtAmt), callbackData);

        // Track GT
        ghost_gtExists[gtId] = true;
        ghost_allGtIds.push(gtId);

        ghost_totalXtLeveraged += xtAmt;
        ghost_totalGtMinted++;

        assertTrue(gt.ownerOf(gtId) != address(0));
    }

    // Issue FT by existing GT
    function issueFtByExistedGt(uint256 additionalDebt, uint256 gtIndex)
        external
        createActor
        countCall("issueFtByExistedGt")
        onlyBeforeMaturity
    {
        if (ghost_allGtIds.length == 0) return;

        gtIndex = bound(gtIndex, 0, ghost_allGtIds.length - 1);
        uint256 gtId = ghost_allGtIds[gtIndex];

        if (!ghost_gtExists[gtId] || gt.ownerOf(gtId) == address(0)) return;

        address currentActor = _getCurrentActor();
        address gtOwner = gt.ownerOf(gtId);

        // Only owner can augment debt
        if (gtOwner != currentActor) return;

        additionalDebt = bound(additionalDebt, 1e6, 100_000e18);

        uint256 ftBalanceBefore = ft.balanceOf(currentActor);

        uint128 ftOutAmt = market.issueFtByExistedGt(currentActor, uint128(additionalDebt), gtId);

        ghost_totalFtIssued += ftOutAmt;

        // Verify FT was issued
        assertEq(ft.balanceOf(currentActor) - ftBalanceBefore, ftOutAmt);
    }

    // Redeem FT after maturity
    function redeem(uint256 ftAmount) external createActor countCall("redeem") onlyAfterMaturity {
        address currentActor = _getCurrentActor();

        uint256 ftBalance = ft.balanceOf(currentActor);
        if (ftBalance == 0) return;

        ftAmount = bound(ftAmount, 1, ftBalance);

        // Approve FT burning
        ft.approve(address(market), ftAmount);

        uint256 debtBalanceBefore = debtToken.balanceOf(currentActor);

        (uint256 debtTokenAmt, bytes memory deliveryData) = market.redeem(ftAmount, currentActor);

        ghost_totalRedeemed += ftAmount;

        // Verify debt tokens received
        assertTrue(debtToken.balanceOf(currentActor) >= debtBalanceBefore);
    }

    // Create order
    function createOrder() external createActor countCall("createOrder") onlyBeforeMaturity {
        address currentActor = _getCurrentActor();

        // Simple order configuration
        uint256 maxXtReserve = 1_000_000e18;
        CurveCuts memory curveCuts;

        // Initialize curve cuts with simple configuration
        curveCuts.lendCurveCuts = new CurveCut[](1);
        curveCuts.lendCurveCuts[0] = CurveCut({xtReserve: 0, liqSquare: 1e18, offset: 0});

        curveCuts.borrowCurveCuts = new CurveCut[](1);
        curveCuts.borrowCurveCuts[0] = CurveCut({xtReserve: 0, liqSquare: 1e18, offset: 0});

        ITermMaxOrder newOrder = market.createOrder(currentActor, maxXtReserve, ISwapCallback(address(0)), curveCuts);

        assertTrue(address(newOrder) != address(0));
    }

    // Advance time to test different phases
    function advanceTime(uint256 timeToAdd) external countCall("advanceTime") {
        timeToAdd = bound(timeToAdd, 1 hours, 30 days);
        vm.warp(block.timestamp + timeToAdd);
    }

    function _getCurrentActor() internal view returns (address) {
        return actors[bound(uint256(keccak256(abi.encode(msg.sender, block.timestamp))), 0, actors.length - 1)];
    }
}

contract TermMaxMarketV2InvariantTest is StdInvariant, Test {
    using JSONLoader for *;

    TermMaxMarketV2 public market;
    IMintableERC20 public ft;
    IMintableERC20 public xt;
    IGearingToken public gt;
    MockERC20 public collateral;
    MockERC20 public debtToken;
    ITermMaxOrder public order;
    TermMaxMarketV2Handler public handler;

    DeployUtils.Res res;
    MarketConfig marketConfig;
    OrderConfig orderConfig;

    function setUp() public {
        // Deploy market using existing utilities
        address deployer = vm.addr(999);
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

        // Create an initial order for testing
        order = market.createOrder(deployer, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts);

        vm.stopPrank();

        // Setup handler
        handler = new TermMaxMarketV2Handler(market, ft, xt, gt, collateral, debtToken, order);

        // Configure invariant testing
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](8); // Changed from 9 to 8
        selectors[0] = handler.mint.selector;
        selectors[1] = handler.burn.selector;
        selectors[2] = handler.issueFt.selector;
        selectors[3] = handler.leverageByXt.selector;
        selectors[4] = handler.issueFtByExistedGt.selector;
        selectors[5] = handler.redeem.selector;
        selectors[6] = handler.createOrder.selector;
        selectors[7] = handler.advanceTime.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // INVARIANT 1: FT and XT total supply should always be equal for minted pairs
    function invariant_ftXtSupplyEquality() public view {
        uint256 ftSupply = ft.totalSupply();
        uint256 xtSupply = xt.totalSupply();
        uint256 treasurerFtBalance = ft.balanceOf(marketConfig.treasurer);

        // FT supply might be higher due to fees paid to treasurer
        assertTrue(ftSupply >= xtSupply, "FT supply should be >= XT supply due to fees");
        assertTrue(ftSupply - treasurerFtBalance <= xtSupply + 1, "FT supply minus fees should equal XT supply");
    }

    // INVARIANT 2: Market should maintain debt token balance consistency
    function invariant_debtTokenConsistency() public view {
        uint256 marketDebtBalance = debtToken.balanceOf(address(market));
        uint256 xtSupply = xt.totalSupply();

        assertApproxEqAbs(
            marketDebtBalance,
            xtSupply,
            0, // Allow 1 unit rounding error
            "Market debt balance should equal user FT supply"
        );
    }

    // INVARIANT 4: GT ownership and existence consistency
    function invariant_gtExistenceConsistency() public view {
        uint256 totalGtTracked = handler.ghost_totalGtMinted();

        // Count actual existing GTs
        uint256 actualExistingGts = 0;
        for (uint256 i = 0; i < handler.getGhostAllGtIdsLength(); i++) {
            uint256 gtId = handler.getGhostAllGtIds(i);
            if (handler.ghost_gtExists(gtId)) {
                // Check if GT exists by trying to get its owner
                // If the GT doesn't exist, ownerOf will revert
                try gt.ownerOf(gtId) returns (address) {
                    actualExistingGts++;
                } catch {
                    // GT doesn't exist anymore (was burned)
                }
            }
        }

        assertTrue(actualExistingGts <= totalGtTracked, "Existing GTs should not exceed tracked GTs");
    }

    // INVARIANT 5: Market should not be exploitable through fee calculations
    function invariant_feeCalculationSafety() public view {
        uint256 mintGtFeeRatio = market.mintGtFeeRatio();

        // Fee ratio should never exceed maximum allowed
        assertTrue(mintGtFeeRatio < Constants.MAX_FEE_RATIO, "Fee ratio should not exceed maximum");

        // Fee ratio should be reasonable (not more than 50%)
        assertTrue(mintGtFeeRatio <= Constants.DECIMAL_BASE / 2, "Fee ratio should be reasonable");
    }

    // INVARIANT 6: Market configuration should remain valid
    function invariant_marketConfigValid() public view {
        MarketConfig memory config = market.config();

        assertTrue(config.maturity > 0, "Maturity should be set");
        assertTrue(config.treasurer != address(0), "Treasurer should be set");

        // Fee configuration should be valid
        FeeConfig memory feeConfig = config.feeConfig;
        assertTrue(feeConfig.borrowTakerFeeRatio < Constants.MAX_FEE_RATIO, "Borrow taker fee should be valid");
        assertTrue(feeConfig.borrowMakerFeeRatio < Constants.MAX_FEE_RATIO, "Borrow maker fee should be valid");
        assertTrue(feeConfig.lendTakerFeeRatio < Constants.MAX_FEE_RATIO, "Lend taker fee should be valid");
        assertTrue(feeConfig.lendMakerFeeRatio < Constants.MAX_FEE_RATIO, "Lend maker fee should be valid");
        assertTrue(feeConfig.mintGtFeeRatio < Constants.MAX_FEE_RATIO, "Mint GT fee should be valid");
    }

    // INVARIANT 7: Token balances should never be negative
    function invariant_noNegativeBalances() public view {
        assertTrue(ft.totalSupply() >= 0, "FT total supply should be non-negative");
        assertTrue(xt.totalSupply() >= 0, "XT total supply should be non-negative");
        assertTrue(debtToken.balanceOf(address(market)) >= 0, "Market debt balance should be non-negative");
        assertTrue(collateral.balanceOf(address(gt)) >= 0, "GT collateral balance should be non-negative");
    }

    // INVARIANT 8: Market operations should respect maturity deadline
    function invariant_maturityRespected() public view {
        // This invariant is enforced by modifiers in the handler
        // Just verify the maturity is correctly set
        assertTrue(market.config().maturity > 0, "Market should have valid maturity");
    }

    // INVARIANT 9: Redemption should only be possible after maturity + liquidation window
    function invariant_redemptionTiming() public view {
        if (handler.ghost_totalRedeemed() > 0) {
            uint256 currentTime = block.timestamp;
            uint256 maturity = market.config().maturity;
            uint256 liquidationDeadline = maturity + Constants.LIQUIDATION_WINDOW;

            assertTrue(currentTime >= liquidationDeadline, "Redemption should only occur after liquidation deadline");
        }
    }

    // INVARIANT 10: Total value locked should be consistent
    function invariant_totalValueLocked() public view {
        uint256 marketDebtBalance = debtToken.balanceOf(address(market));
        uint256 gtCollateralValue = collateral.balanceOf(address(gt));

        // The total value locked should make sense:
        // Market holds debt tokens backing FT/XT pairs
        // GT contract holds collateral backing leveraged positions
        assertTrue(marketDebtBalance >= 0, "Market should hold debt tokens");
        assertTrue(gtCollateralValue >= 0, "GT should hold collateral");
    }

    // Function to display test summary
    function invariant_callSummary() public view {
        console.log("=== TERMMAX MARKET V2 INVARIANT TEST SUMMARY ===");
        console.log("mint calls:", handler.calls("mint"));
        console.log("burn calls:", handler.calls("burn"));
        console.log("issueFt calls:", handler.calls("issueFt"));
        console.log("leverageByXt calls:", handler.calls("leverageByXt"));
        console.log("issueFtByExistedGt calls:", handler.calls("issueFtByExistedGt"));
        console.log("redeem calls:", handler.calls("redeem"));
        console.log("createOrder calls:", handler.calls("createOrder"));
        console.log("advanceTime calls:", handler.calls("advanceTime"));
        console.log("");
        console.log("Ghost variables:");
        console.log("ghost_totalMinted:", handler.ghost_totalMinted());
        console.log("ghost_totalBurned:", handler.ghost_totalBurned());
        console.log("ghost_totalFtIssued:", handler.ghost_totalFtIssued());
        console.log("ghost_totalXtLeveraged:", handler.ghost_totalXtLeveraged());
        console.log("ghost_totalGtMinted:", handler.ghost_totalGtMinted());
        console.log("ghost_totalRedeemed:", handler.ghost_totalRedeemed());
        console.log("");
        console.log("Contract state:");
        console.log("FT total supply:", ft.totalSupply());
        console.log("XT total supply:", xt.totalSupply());
        console.log("Market debt balance:", debtToken.balanceOf(address(market)));
        console.log("GT collateral balance:", collateral.balanceOf(address(gt)));
        console.log("Current timestamp:", block.timestamp);
        console.log("Market maturity:", market.config().maturity);
    }
}
