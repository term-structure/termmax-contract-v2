// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {OrderConfig, CurveCuts, FeeConfig, GtConfig} from "contracts/storage/TermMaxStorage.sol";
import {ITermMaxVault} from "contracts/vault/ITermMaxVault.sol";
import {OrderInfo} from "contracts/vault/VaultStorage.sol";
import {PendingAddress, PendingUint192} from "contracts/lib/PendingLib.sol";

contract MarketViewer {
    struct LoanPosition {
        uint256 loanId;
        uint256 collateralAmt;
        uint256 debtAmt;
    }

    struct LoanPositionV2 {
        address owners;
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
        position.gtInfo = new LoanPosition[](balance);

        for (uint256 i = 0; i < balance; ++i) {
            uint256 loanId = gtNft.tokenOfOwnerByIndex(owner, i);
            position.gtInfo[i].loanId = loanId;
            (, uint128 debtAmt,, bytes memory collateralData) = gt.loanInfo(loanId);
            position.gtInfo[i].debtAmt = debtAmt;
            position.gtInfo[i].collateralAmt = _decodeAmount(collateralData);
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
        LoanPosition[] memory loanPositions = new LoanPosition[](balance);
        for (uint256 i = 0; i < balance; ++i) {
            uint256 loanId = gt.tokenOfOwnerByIndex(owner, i);
            (, uint128 debtAmt,, bytes memory collateralData) = gt.loanInfo(loanId);
            loanPositions[i].loanId = loanId;
            loanPositions[i].debtAmt = debtAmt;
            loanPositions[i].collateralAmt = _decodeAmount(collateralData);
        }
        return loanPositions;
    }

    function getAllLoanPositionV2(ITermMaxMarket market) external view returns (LoanPositionV2[] memory) {
        (,, IGearingToken gtNft,,) = market.tokens();
        GtConfig memory config = gtNft.getGtConfig();
        uint256 supply = gtNft.totalSupply();
        LoanPositionV2[] memory loanPositions = new LoanPositionV2[](supply);
        for (uint256 i = 0; i < supply; ++i) {
            uint256 loanId = gtNft.tokenByIndex(i);
            (address owner, uint128 debtAmt, uint128 ltv, bytes memory collateralData) = gtNft.loanInfo(loanId);
            (bool isLiquidable, uint128 maxRepayAmt) = gtNft.getLiquidationInfo(loanId);
            loanPositions[i].loanId = loanId;
            loanPositions[i].debtAmt = debtAmt;
            loanPositions[i].collateralAmt = _decodeAmount(collateralData);
            loanPositions[i].owners = gtNft.ownerOf(loanId);
            loanPositions[i].ltv = ltv;
            loanPositions[i].isHealthy = ltv >= config.loanConfig.liquidationLtv;
            loanPositions[i].isLiquidable = isLiquidable;
            loanPositions[i].maxRepayAmt = maxRepayAmt;
        }
        return loanPositions;
    }

    function getOrderState(ITermMaxOrder order) external view returns (OrderState memory orderState) {
        ITermMaxMarket market = order.market();
        (,, IGearingToken gt,,) = market.tokens();

        (OrderConfig memory orderConfig) = order.orderConfig();
        (uint256 ftReserve, uint256 xtReserve) = order.tokenReserves();
        if (orderConfig.gtId != 0) {
            (, uint128 debtAmt,, bytes memory collateralData) = gt.loanInfo(orderConfig.gtId);
            orderState.collateralReserve = _decodeAmount(collateralData);
            orderState.debtReserve = debtAmt;
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

    function _decodeAmount(bytes memory collateralData) internal pure returns (uint256) {
        return abi.decode(collateralData, (uint256));
    }
}
