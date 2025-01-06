// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FixedInterestERC4626
 * @notice An ERC4626 vault with fixed interest rate, maturity date, and deposit capacity
 * @dev Interest must be prepaid for maximum deposit amount until maturity
 */
contract FixedInterestERC4626 is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    // Interest rate in basis points per year (1 basis point = 0.01%)
    uint256 public interestRatePerYear;
    // Maturity timestamp
    uint256 public maturityTime;
    // Maximum deposit capacity
    uint256 public depositCapacity;
    // Last time virtual assets were updated
    uint256 public lastUpdateTime;
    // Virtual total assets (scaled by 1e18)
    uint256 public virtualTotalAssets;
    // Real total assets
    uint256 public realTotalAssets;
    // Prepaid interest amount
    uint256 public prepaidInterest;

    // Constants for market timing restrictions
    uint256 public constant RAPID_TRADING_WINDOW = 90 days;

    // Track user's last withdrawal time
    mapping(address => uint256) public lastWithdrawalTime;

    event VirtualAssetsUpdated(uint256 oldVirtualAssets, uint256 newVirtualAssets);
    event PrepaidInterestAdded(uint256 amount, uint256 newTotal);
    event VaultParametersUpdated(uint256 newInterestRate, uint256 newMaturityTime, uint256 newDepositCapacity);

    error InsufficientPrepaidInterest(uint256 required, uint256 provided);
    error MaturityNotReached();
    error InvalidMaturityTime();
    error InvalidInterestRate();
    error RapidTradingRestricted(uint256 nextAllowedEntry);

    /**
     * @dev Constructor to create a new fixed interest vault
     * @param asset_ The underlying asset token
     * @param name_ Name of the vault token
     * @param symbol_ Symbol of the vault token
     * @param interestRatePerYear_ Annual interest rate in basis points (e.g., 500 = 5%)
     * @param maturityTime_ Timestamp when the vault matures
     * @param depositCapacity_ Maximum amount that can be deposited
     * @param initialInterest_ Initial prepaid interest amount
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 interestRatePerYear_,
        uint256 maturityTime_,
        uint256 depositCapacity_,
        uint256 initialInterest_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _updateVaultParameters(interestRatePerYear_, maturityTime_, depositCapacity_, initialInterest_);
        lastUpdateTime = block.timestamp;
        virtualTotalAssets = 0;
        realTotalAssets = 0;
    }

    // redeem()

    // -market-redeem curator weight queue market1 market2 market3

    // timelock queue Morpho market - interest.

    // deposit -markets

    /**
     * @dev Calculate required prepaid interest for given parameters
     */
    function calculateRequiredInterest(
        uint256 interestRate_,
        uint256 maturityTime_,
        uint256 depositCapacity_
    ) public view returns (uint256) {
        if (maturityTime_ <= block.timestamp) revert InvalidMaturityTime();
        if (interestRate_ == 0) revert InvalidInterestRate();

        uint256 timeToMaturity = maturityTime_ - block.timestamp;
        uint256 yearFraction = (timeToMaturity * 1e18) / (365 days);

        // Calculate interest: depositCapacity * rate * timeToMaturity / 365 days
        return (depositCapacity_ * interestRate_ * yearFraction) / (10000 * 1e18);
    }

    /**
     * @dev Update vault parameters with new values
     * @notice Can only be called by owner and requires sufficient prepaid interest
     */
    function updateVaultParameters(
        uint256 newInterestRate,
        uint256 newMaturityTime,
        uint256 newDepositCapacity,
        uint256 additionalInterest
    ) external onlyOwner {
        if (block.timestamp < maturityTime) {
            // Before maturity: can only increase values
            if (newInterestRate < interestRatePerYear) revert InvalidInterestRate();
            if (newMaturityTime < maturityTime) revert InvalidMaturityTime();
            if (newDepositCapacity < depositCapacity) revert InvalidMaturityTime();
        }

        _updateVaultParameters(newInterestRate, newMaturityTime, newDepositCapacity, additionalInterest);
    }

    /**
     * @dev Internal function to update vault parameters
     */
    function _updateVaultParameters(
        uint256 newInterestRate,
        uint256 newMaturityTime,
        uint256 newDepositCapacity,
        uint256 additionalInterest
    ) internal {
        if (newMaturityTime <= block.timestamp) revert InvalidMaturityTime();
        if (newInterestRate == 0) revert InvalidInterestRate();

        // Calculate required interest for new parameters
        uint256 requiredInterest = calculateRequiredInterest(newInterestRate, newMaturityTime, newDepositCapacity);

        // Transfer additional interest if needed
        if (additionalInterest > 0) {
            IERC20(asset()).safeTransferFrom(msg.sender, address(this), additionalInterest);
            prepaidInterest += additionalInterest;
        }

        // Verify sufficient prepaid interest
        if (prepaidInterest < requiredInterest) {
            revert InsufficientPrepaidInterest(requiredInterest, prepaidInterest);
        }

        // Update parameters
        interestRatePerYear = newInterestRate;
        maturityTime = newMaturityTime;
        depositCapacity = newDepositCapacity;

        emit VaultParametersUpdated(newInterestRate, newMaturityTime, newDepositCapacity);
    }

    /**
     * @dev Update virtual assets based on time elapsed and interest rate
     * @notice Uses simple interest calculation to match exact annual interest rate
     */
    function _updateVirtualAssets() internal {
        if (lastUpdateTime == block.timestamp || virtualTotalAssets == 0) return;

        uint256 timeElapsed = block.timestamp - lastUpdateTime;

        // Simple interest calculation: principal * (1 + rate * time)
        // Where rate is annual rate in basis points, time is fraction of year
        uint256 yearFraction = (timeElapsed * 1e18) / (365 days);
        uint256 interestAmount = (virtualTotalAssets * interestRatePerYear * yearFraction) / (10000 * 1e18);

        uint256 oldVirtualAssets = virtualTotalAssets;
        virtualTotalAssets = virtualTotalAssets + interestAmount;
        lastUpdateTime = block.timestamp;

        emit VirtualAssetsUpdated(oldVirtualAssets, virtualTotalAssets);
    }

    /**
     * @dev Get current virtual assets with accrued interest
     * @notice Uses simple interest calculation to match exact annual interest rate
     */
    function _getCurrentVirtualAssets() internal view returns (uint256) {
        if (lastUpdateTime == block.timestamp || virtualTotalAssets == 0) {
            return virtualTotalAssets;
        }

        uint256 timeElapsed = block.timestamp - lastUpdateTime;

        // Simple interest calculation: principal * (1 + rate * time)
        uint256 yearFraction = (timeElapsed * 1e18) / (365 days);
        uint256 interestAmount = (virtualTotalAssets * interestRatePerYear * yearFraction) / (10000 * 1e18);

        return virtualTotalAssets + interestAmount;
    }

    /**
     * @dev Check if user is attempting rapid trading
     * Reverts if user is trying to deposit after a recent withdrawal
     */
    function _checkRapidTrading(address user) internal view {
        uint256 lastWithdraw = lastWithdrawalTime[user];
        if (lastWithdraw != 0 && block.timestamp < lastWithdraw + RAPID_TRADING_WINDOW) {
            revert RapidTradingRestricted(lastWithdraw + RAPID_TRADING_WINDOW);
        }
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view override returns (uint256) {
        return depositCapacity - realTotalAssets;
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address owner) public view override returns (uint256) {
        uint256 maxDeposit_ = maxDeposit(owner);
        if (maxDeposit_ == 0) return 0;

        uint256 supply = totalSupply();
        if (supply == 0) return maxDeposit_;

        return (maxDeposit_ * supply) / totalAssets();
    }

    /**
     * @dev Get total assets, falling back to real assets if virtual assets exceed limit
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 currentVirtualAssets = _getCurrentVirtualAssets();
        uint256 maxAllowedAssets = realTotalAssets + prepaidInterest;

        // If virtual assets exceed real assets + prepaid interest, return real assets
        return currentVirtualAssets > maxAllowedAssets ? realTotalAssets : currentVirtualAssets;
    }

    /**
     * @dev Check if the vault has reached maturity
     */
    function isMatured() public view returns (bool) {
        return block.timestamp >= maturityTime;
    }

    /**
     * @dev Deposit assets into the vault
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        _checkRapidTrading(receiver);
        _updateVirtualAssets();
        virtualTotalAssets += assets;
        realTotalAssets += assets;
        return super.deposit(assets, receiver);
    }

    /**
     * @dev Withdraw assets from the vault
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256) {
        _updateVirtualAssets();
        virtualTotalAssets -= assets;
        realTotalAssets -= assets;

        // Record withdrawal time
        lastWithdrawalTime[owner] = block.timestamp;

        // Return only principal, no interest
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @dev Mint shares of the vault
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        _checkRapidTrading(receiver);
        uint256 assets = previewMint(shares);
        virtualTotalAssets += assets;
        realTotalAssets += assets;
        return super.mint(shares, receiver);
    }

    /**
     * @dev Redeem shares from the vault
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        uint256 assets = previewRedeem(shares);
        virtualTotalAssets -= assets;
        realTotalAssets -= assets;

        // Record withdrawal time
        lastWithdrawalTime[owner] = block.timestamp;

        // Return only principal, no interest
        return super.redeem(shares, receiver, owner);
    }

    /**
     * @dev Convert assets to shares using total assets
     */
    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 currentTotalAssets = totalAssets();
        return supply == 0 ? assets : (assets * supply) / currentTotalAssets;
    }

    /**
     * @dev Convert shares to assets using total assets
     */
    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : (shares * totalAssets()) / supply;
    }

    /**
     * @dev Get time until user can deposit again after withdrawal
     * @return 0 if allowed to deposit, otherwise remaining time
     */
    function getNextAllowedEntry(address user) public view returns (uint256) {
        uint256 lastWithdraw = lastWithdrawalTime[user];
        if (lastWithdraw == 0 || block.timestamp >= lastWithdraw + RAPID_TRADING_WINDOW) {
            return 0;
        }
        return lastWithdraw + RAPID_TRADING_WINDOW - block.timestamp;
    }
}
