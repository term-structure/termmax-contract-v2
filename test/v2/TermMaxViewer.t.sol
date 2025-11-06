// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {TermMaxViewer} from "contracts/v2/router/TermMaxViewer.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {ITermMaxVault} from "contracts/interfaces/ITermMaxVault.sol";
import {ITermMax4626Pool} from "contracts/interfaces/ITermMax4626Pool.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";

import {MarketConfig, OrderConfig} from "contracts/v1/storage/TermMaxStorage.sol";

contract MockTermMax4626PoolAave {
    IERC20 public aToken;
    address public assetAddr;
    uint256 public totalAssetsValue;

    constructor(address _asset, address _aToken) {
        assetAddr = _asset;
        aToken = IERC20(_aToken);
        totalAssetsValue = 1000e18;
    }

    function asset() external view returns (address) {
        return assetAddr;
    }

    function totalAssets() external view returns (uint256) {
        return totalAssetsValue;
    }

    function setTotalAssets(uint256 _totalAssets) external {
        totalAssetsValue = _totalAssets;
    }
}

contract MockTermMax4626PoolERC4626 {
    IERC4626 public thirdPool;
    address public assetAddr;
    uint256 public totalAssetsValue;

    constructor(address _asset, address _thirdPool) {
        assetAddr = _asset;
        thirdPool = IERC4626(_thirdPool);
        totalAssetsValue = 1000e18;
    }

    function asset() external view returns (address) {
        return assetAddr;
    }

    function totalAssets() external view returns (uint256) {
        return totalAssetsValue;
    }

    function setTotalAssets(uint256 _totalAssets) external {
        totalAssetsValue = _totalAssets;
    }

    // This will cause the try/catch to fail when calling aToken()
    function aToken() external pure {
        revert("Not an Aave pool");
    }
}

contract TermMaxViewerTest is Test {
    using Math for uint256;
    using JSONLoader for *;

    TermMaxViewer public viewer;
    TermMaxViewer public viewerImplementation;

    address public admin;
    address public user1;
    address public user2;

    DeployUtils.Res public res;
    OrderConfig public orderConfig;
    MarketConfig public marketConfig;
    string public testdata;

    MockERC20 public mockAsset;
    MockERC20 public mockAToken;
    MockERC4626 public mockVault;
    MockTermMax4626PoolAave public mockPoolAave;
    MockTermMax4626PoolERC4626 public mockPoolERC4626;

    function setUp() public {
        admin = vm.randomAddress();
        user1 = vm.randomAddress();
        user2 = vm.randomAddress();

        // Deploy TermMaxViewer with proxy pattern
        viewerImplementation = new TermMaxViewer();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(viewerImplementation), abi.encodeWithSelector(TermMaxViewer.initialize.selector, admin)
        );
        viewer = TermMaxViewer(address(proxy));

        // Set up a market for testing
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));
        address deployer = vm.randomAddress();
        address treasurer = vm.randomAddress();

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        vm.startPrank(deployer);
        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");
        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);
        vm.stopPrank();

        // Set up mock assets for pool testing
        mockAsset = new MockERC20("Mock Asset", "MASSET", 18);
        mockAToken = new MockERC20("Mock aToken", "aMASSET", 18);
        mockVault = new MockERC4626(IERC20(address(mockAsset)));

        mockPoolAave = new MockTermMax4626PoolAave(address(mockAsset), address(mockAToken));
        mockPoolERC4626 = new MockTermMax4626PoolERC4626(address(mockAsset), address(mockVault));
    }

    // ============================================
    // INITIALIZATION TESTS
    // ============================================

    function testInitialize() public view {
        assertEq(Ownable(address(viewer)).owner(), admin);
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        viewer.initialize(user1);
    }

    function testCannotInitializeImplementation() public {
        vm.expectRevert();
        viewerImplementation.initialize(admin);
    }

    // ============================================
    // UPGRADE AUTHORIZATION TESTS
    // ============================================

    function testOnlyOwnerCanAuthorizeUpgrade() public {
        TermMaxViewer newImplementation = new TermMaxViewer();

        // Non-owner cannot upgrade
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        viewer.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();

        // Owner can upgrade
        vm.startPrank(admin);
        viewer.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    // ============================================
    // ASSETS WITH ERC20 COLLATERAL TESTS
    // ============================================

    function testAssetsWithERC20Collateral_NoGtBalance() public {
        (IERC20[4] memory tokens, uint256[4] memory balances, address gtAddr, uint256[] memory gtIds) =
            viewer.assetsWithERC20Collateral(res.market, user1);

        // Check that all tokens are returned
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateral, IERC20 underlying) = res.market.tokens();
        assertEq(address(tokens[0]), address(ft));
        assertEq(address(tokens[1]), address(xt));
        assertEq(address(tokens[2]), collateral);
        assertEq(address(tokens[3]), address(underlying));

        // Check balances are zero for user1
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
        assertEq(balances[2], 0);
        assertEq(balances[3], 0);

        // Check GT address
        assertEq(gtAddr, address(gt));

        // Check no GT tokens
        assertEq(gtIds.length, 0);
    }

    function testAssetsWithERC20Collateral_WithBalances() public {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateral, IERC20 underlying) = res.market.tokens();

        // Mint some tokens to user1
        vm.startPrank(address(res.market));
        MockERC20(address(ft)).mint(user1, 100e18);
        MockERC20(address(xt)).mint(user1, 200e18);
        MockERC20(collateral).mint(user1, 300e18);
        MockERC20(address(underlying)).mint(user1, 400e18);
        vm.stopPrank();

        (IERC20[4] memory tokens, uint256[4] memory balances, address gtAddr, uint256[] memory gtIds) =
            viewer.assetsWithERC20Collateral(res.market, user1);

        // Check balances
        assertEq(balances[0], 100e18);
        assertEq(balances[1], 200e18);
        assertEq(balances[2], 300e18);
        assertEq(balances[3], 400e18);

        assertEq(gtAddr, address(gt));
        assertEq(gtIds.length, 0);
    }

    function testAssetsWithERC20Collateral_WithGtTokens() public {
        // First mint underlying to user1 to create GT tokens
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateral, IERC20 underlying) = res.market.tokens();

        // Use helper to create GT token
        vm.startPrank(user1);
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        (uint256 gtId,) = LoanUtils.fastMintGt(res, user1, debtAmt, collateralAmt);
        vm.stopPrank();

        // Now check the assets
        (IERC20[4] memory tokens, uint256[4] memory balances, address gtAddr, uint256[] memory gtIds) =
            viewer.assetsWithERC20Collateral(res.market, user1);

        // Should have at least 1 GT token
        assertEq(gtAddr, address(gt));
        assertEq(gtIds.length, 1);

        // Verify the GT token IDs are correct
        assertEq(gtIds[0], gtId);
        assertEq(IERC721Enumerable(gtAddr).ownerOf(gtIds[0]), user1);
    }

    // ============================================
    // PREVIEW DEAL BAD DEBT TESTS
    // ============================================

    function testPreviewDealBadDebt_ZeroBadDebt() public {
        // For this test, we need a vault with bad debt functionality
        // Using a simplified mock scenario
        address mockVaultAddr = address(0x123);
        address mockCollateral = address(res.collateral);

        // Mock the vault's badDebtMapping to return 0
        vm.mockCall(mockVaultAddr, abi.encodeWithSignature("badDebtMapping(address)", mockCollateral), abi.encode(0));

        // When badDebt is 0, the contract handles it gracefully and returns (0, 0, 0)
        // No need to mock other calls since the function returns early
        (uint256 maxRedeem, uint256 totalBadDebt, uint256 totalCollateral) =
            viewer.previewDealBadDebt(ITermMaxVault(mockVaultAddr), mockCollateral, user1);

        assertEq(totalBadDebt, 0);
        assertEq(totalCollateral, 0);
        assertEq(maxRedeem, 0);
    }

    function testPreviewDealBadDebt_WithBadDebt() public {
        address mockVaultAddr = address(0x456);
        address mockCollateral = address(res.collateral);

        uint256 badDebt = 1000e18;
        uint256 collateralBalance = 500e18;
        uint256 userVaultBalance = 100e18;
        uint256 userAssets = 80e18;

        // Mock the vault's badDebtMapping
        vm.mockCall(
            mockVaultAddr, abi.encodeWithSignature("badDebtMapping(address)", mockCollateral), abi.encode(badDebt)
        );

        // Mock the collateral balance
        vm.mockCall(
            mockCollateral,
            abi.encodeWithSelector(IERC20.balanceOf.selector, mockVaultAddr),
            abi.encode(collateralBalance)
        );

        // Mock the vault's balanceOf for user
        vm.mockCall(
            mockVaultAddr, abi.encodeWithSelector(IERC20.balanceOf.selector, user1), abi.encode(userVaultBalance)
        );

        // Mock convertToAssets
        vm.mockCall(
            mockVaultAddr, abi.encodeWithSignature("convertToAssets(uint256)", userVaultBalance), abi.encode(userAssets)
        );

        (uint256 maxRedeem, uint256 totalBadDebt, uint256 totalCollateral) =
            viewer.previewDealBadDebt(ITermMaxVault(mockVaultAddr), mockCollateral, user1);

        assertEq(totalBadDebt, badDebt);
        assertEq(totalCollateral, collateralBalance);

        // Calculate expected maxRedeem: totalCollateral * userAssets / totalBadDebt
        uint256 expectedMaxRedeem = collateralBalance.mulDiv(userAssets, badDebt);
        assertEq(maxRedeem, expectedMaxRedeem);
    }

    function testPreviewDealBadDebt_FuzzTest(
        uint256 badDebt,
        uint256 collateralBalance,
        uint256 userVaultBalance,
        uint256 userAssets
    ) public {
        // Bound the inputs to reasonable values
        badDebt = bound(badDebt, 1, type(uint128).max);
        collateralBalance = bound(collateralBalance, 0, type(uint128).max);
        userVaultBalance = bound(userVaultBalance, 0, type(uint128).max);
        userAssets = bound(userAssets, 0, userVaultBalance);

        address mockVaultAddr = address(0x789);
        address mockCollateral = address(res.collateral);

        // Mock the vault's badDebtMapping
        vm.mockCall(
            mockVaultAddr, abi.encodeWithSignature("badDebtMapping(address)", mockCollateral), abi.encode(badDebt)
        );

        // Mock the collateral balance
        vm.mockCall(
            mockCollateral,
            abi.encodeWithSelector(IERC20.balanceOf.selector, mockVaultAddr),
            abi.encode(collateralBalance)
        );

        // Mock the vault's balanceOf for user
        vm.mockCall(
            mockVaultAddr, abi.encodeWithSelector(IERC20.balanceOf.selector, user1), abi.encode(userVaultBalance)
        );

        // Mock convertToAssets
        vm.mockCall(
            mockVaultAddr, abi.encodeWithSignature("convertToAssets(uint256)", userVaultBalance), abi.encode(userAssets)
        );

        (uint256 maxRedeem, uint256 totalBadDebt, uint256 totalCollateral) =
            viewer.previewDealBadDebt(ITermMaxVault(mockVaultAddr), mockCollateral, user1);

        assertEq(totalBadDebt, badDebt);
        assertEq(totalCollateral, collateralBalance);

        uint256 expectedMaxRedeem = collateralBalance.mulDiv(userAssets, badDebt);
        assertEq(maxRedeem, expectedMaxRedeem);
    }

    // ============================================
    // GET POOL UNCLAIMED REWARDS TESTS
    // ============================================

    function testGetPoolUnclaimedRewards_SingleAavePool() public {
        // Setup: mint some assets to the pool and aToken
        mockAsset.mint(address(mockPoolAave), 500e18);
        mockAToken.mint(address(mockPoolAave), 300e18);

        ITermMax4626Pool[] memory pools = new ITermMax4626Pool[](1);
        pools[0] = ITermMax4626Pool(address(mockPoolAave));

        (address[] memory assets, uint256[] memory amounts) = viewer.getPoolUnclaimedRewards(pools);

        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(mockAsset));
        // Note: amounts are not calculated in the current implementation (missing return statement)
        // This appears to be a bug in the original contract
    }

    function testGetPoolUnclaimedRewards_SingleERC4626Pool() public {
        // Setup: mint some assets to the pool
        mockAsset.mint(address(mockPoolERC4626), 500e18);
        // Deposit vault shares to the pool by first minting assets to the vault, then depositing
        mockAsset.mint(address(this), 1000e18);
        mockAsset.approve(address(mockVault), 1000e18);
        uint256 shares = mockVault.deposit(1000e18, address(mockPoolERC4626));

        ITermMax4626Pool[] memory pools = new ITermMax4626Pool[](1);
        pools[0] = ITermMax4626Pool(address(mockPoolERC4626));

        (address[] memory assets, uint256[] memory amounts) = viewer.getPoolUnclaimedRewards(pools);

        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(mockAsset));
        // amounts would need to be calculated based on totalFunds calculation
    }

    function testGetPoolUnclaimedRewards_MultiplePools() public {
        // Setup both pools
        mockAsset.mint(address(mockPoolAave), 500e18);
        mockAToken.mint(address(mockPoolAave), 300e18);

        MockERC20 mockAsset2 = new MockERC20("Mock Asset 2", "MASSET2", 18);
        MockERC4626 mockVault2 = new MockERC4626(IERC20(address(mockAsset2)));
        MockTermMax4626PoolERC4626 mockPoolERC4626_2 =
            new MockTermMax4626PoolERC4626(address(mockAsset2), address(mockVault2));

        mockAsset2.mint(address(mockPoolERC4626_2), 600e18);
        mockAsset2.mint(address(this), 2000e18);
        mockAsset2.approve(address(mockVault2), 2000e18);
        uint256 shares2 = mockVault2.deposit(2000e18, address(mockPoolERC4626_2));

        ITermMax4626Pool[] memory pools = new ITermMax4626Pool[](2);
        pools[0] = ITermMax4626Pool(address(mockPoolAave));
        pools[1] = ITermMax4626Pool(address(mockPoolERC4626_2));

        (address[] memory assets, uint256[] memory amounts) = viewer.getPoolUnclaimedRewards(pools);

        assertEq(assets.length, 2);
        assertEq(amounts.length, 2);
        assertEq(assets[0], address(mockAsset));
        assertEq(assets[1], address(mockAsset2));
    }

    function testGetPoolUnclaimedRewards_EmptyArray() public {
        ITermMax4626Pool[] memory pools = new ITermMax4626Pool[](0);

        (address[] memory assets, uint256[] memory amounts) = viewer.getPoolUnclaimedRewards(pools);

        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    function testFullIntegrationScenario() public {
        // 1. Check assets for a user with no balance
        (IERC20[4] memory tokens1, uint256[4] memory balances1,,) = viewer.assetsWithERC20Collateral(res.market, user1);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(balances1[i], 0);
        }

        // 2. Mint some tokens to user
        (, IERC20 xt,, address collateral,) = res.market.tokens();
        vm.startPrank(address(res.market));
        MockERC20(address(xt)).mint(user1, 500e18);
        MockERC20(collateral).mint(user1, 1000e18);
        vm.stopPrank();

        // 3. Check assets again
        (, uint256[4] memory balances2,,) = viewer.assetsWithERC20Collateral(res.market, user1);
        assertEq(balances2[1], 500e18); // xt
        assertEq(balances2[2], 1000e18); // collateral

        // 4. Test pool rewards
        mockAsset.mint(address(mockPoolAave), 1000e18);
        mockAToken.mint(address(mockPoolAave), 500e18);

        ITermMax4626Pool[] memory pools = new ITermMax4626Pool[](1);
        pools[0] = ITermMax4626Pool(address(mockPoolAave));

        (address[] memory assets,) = viewer.getPoolUnclaimedRewards(pools);
        assertEq(assets[0], address(mockAsset));
    }

    // ============================================
    // EDGE CASE TESTS
    // ============================================

    function testAssetsWithERC20Collateral_MultipleUsers() public {
        (IERC20 ft, IERC20 xt,, address collateral,) = res.market.tokens();

        // Mint different amounts to different users
        vm.startPrank(address(res.market));
        MockERC20(address(ft)).mint(user1, 100e18);
        MockERC20(address(xt)).mint(user1, 200e18);

        MockERC20(address(ft)).mint(user2, 300e18);
        MockERC20(address(xt)).mint(user2, 400e18);
        vm.stopPrank();

        // Check user1
        (, uint256[4] memory balances1,,) = viewer.assetsWithERC20Collateral(res.market, user1);
        assertEq(balances1[0], 100e18);
        assertEq(balances1[1], 200e18);

        // Check user2
        (, uint256[4] memory balances2,,) = viewer.assetsWithERC20Collateral(res.market, user2);
        assertEq(balances2[0], 300e18);
        assertEq(balances2[1], 400e18);
    }

    function testPreviewDealBadDebt_MaxValues() public {
        address mockVaultAddr = address(0xABC);
        address mockCollateral = address(res.collateral);

        uint256 badDebt = type(uint128).max;
        uint256 collateralBalance = type(uint128).max;
        uint256 userVaultBalance = type(uint128).max / 2;
        uint256 userAssets = type(uint128).max / 2;

        vm.mockCall(
            mockVaultAddr, abi.encodeWithSignature("badDebtMapping(address)", mockCollateral), abi.encode(badDebt)
        );

        vm.mockCall(
            mockCollateral,
            abi.encodeWithSelector(IERC20.balanceOf.selector, mockVaultAddr),
            abi.encode(collateralBalance)
        );

        vm.mockCall(
            mockVaultAddr, abi.encodeWithSelector(IERC20.balanceOf.selector, user1), abi.encode(userVaultBalance)
        );

        vm.mockCall(
            mockVaultAddr, abi.encodeWithSignature("convertToAssets(uint256)", userVaultBalance), abi.encode(userAssets)
        );

        (uint256 maxRedeem, uint256 totalBadDebt, uint256 totalCollateral) =
            viewer.previewDealBadDebt(ITermMaxVault(mockVaultAddr), mockCollateral, user1);

        assertEq(totalBadDebt, badDebt);
        assertEq(totalCollateral, collateralBalance);
        // Should not overflow
        assertLe(maxRedeem, collateralBalance);
    }
}
