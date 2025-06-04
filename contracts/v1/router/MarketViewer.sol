// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {IMintableERC20} from "../tokens/IMintableERC20.sol";
import {IGearingToken} from "../tokens/IGearingToken.sol";
import {OrderConfig, CurveCuts, FeeConfig, GtConfig} from "../storage/TermMaxStorage.sol";
import {ITermMaxVault} from "../vault/ITermMaxVault.sol";
import {OrderInfo} from "../vault/VaultStorage.sol";
import {PendingAddress, PendingUint192} from "../lib/PendingLib.sol";
import {OracleAggregator} from "../oracle/OracleAggregator.sol";

interface IPausable {
    function paused() external view returns (bool);
}

contract MarketViewer {
    using Math for uint256;

    struct LoanPosition {
        uint256 loanId;
        uint256 collateralAmt;
        uint256 debtAmt;
    }

    struct LoanPositionV2 {
        address owner;
        uint256 loanId;
        uint256 collateralAmt;
        uint256 debtAmt;
        uint128 ltv;
        bool isHealthy;
        bool isLiquidable;
        uint128 maxRepayAmt;
    }

    struct Position {
        uint256 underlyingBalance;
        uint256 collateralBalance;
        uint256 ftBalance;
        uint256 xtBalance;
        LoanPosition[] gtInfo;
    }

    struct VaultPosition {
        uint256 balance;
        uint256 toAssetBalance;
        uint256 usdValue;
    }

    struct OrderState {
        uint256 collateralReserve;
        uint256 debtReserve;
        uint256 ftReserve;
        uint256 xtReserve;
        uint256 maxXtReserve;
        uint256 gtId;
        CurveCuts curveCuts;
        FeeConfig feeConfig;
    }

    struct VaultInfo {
        string name;
        string symbol;
        address assetAddress;
        // Basic vault metrics
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 apr;
        // Governance settings
        address guardian;
        address curator;
        uint256 timelock;
        uint256 maxDeposit;
        uint64 performanceFeeRate;
        uint256 idleFunds; // asset.balanceOf(address(this))
        // Financial metrics
        uint256 totalFt;
        uint256 accretingPrincipal;
        uint256 annualizedInterest;
        uint256 performanceFee;
        // Queue information
        address[] supplyQueue;
        address[] withdrawQueue;
        // Pending governance updates
        PendingAddress pendingGuardian;
        PendingUint192 pendingTimelock;
        PendingUint192 pendingPerformanceFeeRate;
        uint256 maxMint; // maxMint(address(0))
        uint256 convertToSharesPrice; // convertToShares(One)
        bool isPaused;
    }

    function getPositionDetail(ITermMaxMarket market, address owner) public view returns (Position memory position) {
        (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, address collateral, IERC20 underlying) =
            market.tokens();
        position.underlyingBalance = underlying.balanceOf(owner);
        position.collateralBalance = IERC20(collateral).balanceOf(owner);
        position.ftBalance = ft.balanceOf(owner);
        position.xtBalance = xt.balanceOf(owner);

        IERC721Enumerable gtNft = IERC721Enumerable(address(gt));
        uint256 balance = gtNft.balanceOf(owner);
        LoanPosition[] memory gtInfos = new LoanPosition[](balance);

        uint256 validPositions = 0;
        for (uint256 i = 0; i < balance; ++i) {
            uint256 loanId = gtNft.tokenOfOwnerByIndex(owner, i);
            try gt.loanInfo(loanId) returns (address, uint128 debtAmt, bytes memory collateralData) {
                gtInfos[validPositions].loanId = loanId;
                gtInfos[validPositions].debtAmt = debtAmt;
                gtInfos[validPositions].collateralAmt = _decodeAmount(collateralData);
                validPositions++;
            } catch {
                // Skip this loan ID if loanInfo call fails
            }
        }
        position.gtInfo = new LoanPosition[](validPositions);
        for (uint256 i = 0; i < validPositions; i++) {
            position.gtInfo[i] = gtInfos[i];
        }
    }

    function getPositionDetails(ITermMaxMarket[] memory market, address owner)
        external
        view
        returns (Position[] memory)
    {
        Position[] memory positions = new Position[](market.length);
        for (uint256 i = 0; i < market.length; ++i) {
            positions[i] = getPositionDetail(market[i], owner);
        }
        return positions;
    }

    function getAllLoanPosition(ITermMaxMarket market, address owner) external view returns (LoanPosition[] memory) {
        (,, IGearingToken gt,,) = market.tokens();
        uint256 balance = gt.balanceOf(owner);
        LoanPosition[] memory loanPositionsTmp = new LoanPosition[](balance);

        uint256 validPositions = 0;
        for (uint256 i = 0; i < balance; ++i) {
            uint256 loanId = gt.tokenOfOwnerByIndex(owner, i);
            try gt.loanInfo(loanId) returns (address, uint128 debtAmt, bytes memory collateralData) {
                loanPositionsTmp[validPositions].loanId = loanId;
                loanPositionsTmp[validPositions].debtAmt = debtAmt;
                loanPositionsTmp[validPositions].collateralAmt = _decodeAmount(collateralData);
                validPositions++;
            } catch {
                // Skip this loan ID if loanInfo call fails
            }
        }

        LoanPosition[] memory loanPositions = new LoanPosition[](validPositions);
        for (uint256 i = 0; i < validPositions; i++) {
            loanPositions[i] = loanPositionsTmp[i];
        }
        return loanPositions;
    }

    function getAllLoanPositionV2(ITermMaxMarket market) external view returns (LoanPositionV2[] memory) {
        (,, IGearingToken gtNft,,) = market.tokens();
        GtConfig memory config = gtNft.getGtConfig();
        uint256 supply = gtNft.totalSupply();
        LoanPositionV2[] memory loanPositionsTmp = new LoanPositionV2[](supply);

        uint256 validPositions = 0;
        for (uint256 i = 0; i < supply; ++i) {
            uint256 loanId = gtNft.tokenByIndex(i);
            try gtNft.loanInfo(loanId) returns (address owner, uint128 debtAmt, bytes memory collateralData) {
                loanPositionsTmp[validPositions].loanId = loanId;
                loanPositionsTmp[validPositions].debtAmt = debtAmt;
                loanPositionsTmp[validPositions].collateralAmt = _decodeAmount(collateralData);
                loanPositionsTmp[validPositions].owner = owner;
                try gtNft.getLiquidationInfo(loanId) returns (bool isLiquidable, uint128 ltv, uint128 maxRepayAmt) {
                    loanPositionsTmp[validPositions].ltv = ltv;
                    loanPositionsTmp[validPositions].isHealthy = ltv >= config.loanConfig.liquidationLtv;
                    loanPositionsTmp[validPositions].isLiquidable = isLiquidable;
                    loanPositionsTmp[validPositions].maxRepayAmt = maxRepayAmt;
                } catch {
                    // Skip this loan ID if getLiquidationInfo call fails
                }
                validPositions++;
            } catch {
                // Skip this loan ID if loanInfo call fails
                continue;
            }
        }

        LoanPositionV2[] memory loanPositions = new LoanPositionV2[](validPositions);
        for (uint256 i = 0; i < validPositions; i++) {
            loanPositions[i] = loanPositionsTmp[i];
        }
        return loanPositions;
    }

    function getVaultBalance(address user, ITermMaxVault[] memory vaults, OracleAggregator oracleAggregator)
        external
        view
        returns (VaultPosition[] memory)
    {
        VaultPosition[] memory vaultPositions = new VaultPosition[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            address asset = vaults[i].asset();
            uint256 balance = vaults[i].balanceOf(user);
            vaultPositions[i].balance = balance;
            vaultPositions[i].toAssetBalance = vaults[i].convertToAssets(balance);
            try oracleAggregator.getPrice(asset) returns (uint256 price, uint8) {
                uint8 assetDecimals = IERC20Metadata(asset).decimals();
                vaultPositions[i].usdValue = vaultPositions[i].toAssetBalance.mulDiv(price, 10 ** assetDecimals);
            } catch {
                vaultPositions[i].usdValue = 0;
            }
        }
        return vaultPositions;
    }

    function getOrderState(ITermMaxOrder order) external view returns (OrderState memory orderState) {
        ITermMaxMarket market = order.market();
        (,, IGearingToken gt,,) = market.tokens();

        (OrderConfig memory orderConfig) = order.orderConfig();
        (uint256 ftReserve, uint256 xtReserve) = order.tokenReserves();
        if (orderConfig.gtId != 0) {
            try gt.loanInfo(orderConfig.gtId) returns (address, uint128 debtAmt, bytes memory collateralData) {
                orderState.collateralReserve = _decodeAmount(collateralData);
                orderState.debtReserve = debtAmt;
            } catch {
                // If loan info is unavailable, set defaults
                orderState.collateralReserve = 0;
                orderState.debtReserve = 0;
            }
        }

        orderState.ftReserve = ftReserve;
        orderState.xtReserve = xtReserve;
        orderState.maxXtReserve = orderConfig.maxXtReserve;
        orderState.gtId = orderConfig.gtId;
        orderState.curveCuts = orderConfig.curveCuts;
        orderState.feeConfig = orderConfig.feeConfig;
        return orderState;
    }

    /**
     * @notice Get comprehensive information about a TermMaxVault
     * @param vault The TermMaxVault to query
     * @return vaultInfo The vault information
     */
    function getVaultInfo(ITermMaxVault vault) external view returns (VaultInfo memory vaultInfo) {
        IERC20 asset = IERC20(vault.asset());

        // Basic vault metrics
        vaultInfo.name = vault.name();
        vaultInfo.symbol = vault.symbol();
        vaultInfo.assetAddress = address(asset);
        vaultInfo.totalAssets = vault.totalAssets();
        vaultInfo.totalSupply = vault.totalSupply();
        vaultInfo.apr = vault.apr();

        // Governance settings
        vaultInfo.guardian = vault.guardian();
        vaultInfo.curator = vault.curator();
        vaultInfo.timelock = vault.timelock();
        vaultInfo.maxDeposit = vault.maxDeposit(address(0));

        vaultInfo.idleFunds = asset.balanceOf(address(vault));

        // Financial metrics
        vaultInfo.totalFt = vault.totalFt();
        vaultInfo.accretingPrincipal = vault.accretingPrincipal();
        vaultInfo.annualizedInterest = vault.annualizedInterest();
        vaultInfo.performanceFeeRate = vault.performanceFeeRate();
        vaultInfo.performanceFee = vault.performanceFee();

        // Queue information
        uint256 supplyQueueLength = vault.supplyQueueLength();
        vaultInfo.supplyQueue = new address[](supplyQueueLength);
        for (uint256 i = 0; i < supplyQueueLength; i++) {
            vaultInfo.supplyQueue[i] = vault.supplyQueue(i);
        }

        uint256 withdrawQueueLength = vault.withdrawQueueLength();
        vaultInfo.withdrawQueue = new address[](withdrawQueueLength);
        for (uint256 i = 0; i < withdrawQueueLength; i++) {
            vaultInfo.withdrawQueue[i] = vault.withdrawQueue(i);
        }

        // Pending governance updates
        vaultInfo.pendingGuardian = vault.pendingGuardian();
        vaultInfo.pendingTimelock = vault.pendingTimelock();
        vaultInfo.pendingPerformanceFeeRate = vault.pendingPerformanceFeeRate();

        vaultInfo.maxMint = vault.maxMint(address(0));
        uint256 one = 10 ** vault.decimals();
        vaultInfo.convertToSharesPrice = vault.convertToShares(one);
        vaultInfo.isPaused = IPausable(address(vault)).paused();
    }

    /**
     * @notice Get information about all orders in a vault
     * @param vault The TermMaxVault to query
     * @return orderInfos Array of information about each order in the vault
     */
    function getVaultOrdersInfo(ITermMaxVault vault) external view returns (OrderState[] memory) {
        uint256 supplyQueueLength = vault.supplyQueueLength();
        OrderState[] memory orderInfos = new OrderState[](supplyQueueLength);

        for (uint256 i = 0; i < supplyQueueLength; i++) {
            address orderAddress = vault.supplyQueue(i);
            ITermMaxOrder order = ITermMaxOrder(orderAddress);
            orderInfos[i] = this.getOrderState(order);
        }

        return orderInfos;
    }

    function getVaultPendingMarkets(ITermMaxVault vault, address[] calldata markets)
        external
        view
        returns (PendingUint192[] memory)
    {
        PendingUint192[] memory pendingMarkets = new PendingUint192[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            pendingMarkets[i] = vault.pendingMarkets(markets[i]);
        }
        return pendingMarkets;
    }

    function _decodeAmount(bytes memory collateralData) internal pure returns (uint256) {
        return abi.decode(collateralData, (uint256));
    }
}
