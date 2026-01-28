// SPDX-License-Identifier:  BUSL-1.1
pragma solidity ^0.8.27;

import {
    ERC4626Upgradeable, Math
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    OwnableUpgradeable,
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IVToken} from "../extensions/venus/IVToken.sol";
import {TransferUtilsV2} from "../lib/TransferUtilsV2.sol";
import {StakingBuffer} from "./StakingBuffer.sol";
import {ERC4626TokenEvents} from "../events/ERC4626TokenEvents.sol";
import {ERC4626TokenErrors} from "../errors/ERC4626TokenErrors.sol";

contract StableERC4626ForVenus is
    StakingBuffer,
    ERC4626Upgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    using TransferUtilsV2 for *;

    uint256 constant PRECISION = 1e18;
    IVToken public thirdPool;
    IERC20 public underlying;
    BufferConfig public bufferConfig;
    uint256 internal withdrawnIncomeAssets;

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address thirdPool_, BufferConfig memory bufferConfig_) public initializer {
        thirdPool = IVToken(thirdPool_);
        address underlying_ = thirdPool.underlying();
        underlying = IERC20(underlying_);
        string memory name =
            string(abi.encodePacked("TermMax Stable VenusERC4626 ", IERC20Metadata(underlying_).name()));
        string memory symbol = string(abi.encodePacked("tmsv", IERC20Metadata(underlying_).symbol()));
        __ERC20_init_unchained(name, symbol);
        __Ownable_init_unchained(admin);
        __ERC4626_init_unchained(IERC20(underlying_));
        __ReentrancyGuard_init_unchained();
        _updateBufferConfig(bufferConfig_);

        emit ERC4626TokenEvents.ERC4626ForVenusInitialized(admin, underlying_, thirdPool_);
    }

    function totalAssets() public view virtual override returns (uint256) {
        // share is 1:1 with underlying
        return super.totalSupply();
    }

    function _deposit(address caller, address recipient, uint256 assets, uint256 shares)
        internal
        virtual
        override
        nonReentrant
    {
        IERC20 assetToken = IERC20(asset());
        assetToken.safeTransferFrom(caller, address(this), assets);
        _depositWithBuffer(address(assetToken));
        _mint(recipient, shares);

        emit Deposit(caller, recipient, assets, shares);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding) internal view virtual override returns (uint256) {
        return assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding) internal view virtual override returns (uint256) {
        return shares;
    }

    function _withdraw(address caller, address recipient, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
        nonReentrant
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        _withdrawWithBuffer(address(underlying), recipient, assets);

        emit Withdraw(caller, recipient, owner, assets, shares);
    }

    function totalIncomeAssets() external view returns (uint256) {
        uint256 assetInPool = _assetInPool(address(0));
        uint256 underlyingBalance = underlying.balanceOf(address(this));
        uint256 totalSupply_ = totalSupply();
        uint256 assetsWithIncome = assetInPool + underlyingBalance + withdrawnIncomeAssets;
        if (assetsWithIncome < totalSupply_) {
            // If total assets with income is less than total supply, return 0
            return 0;
        } else {
            return assetsWithIncome - totalSupply_;
        }
    }

    function currentIncomeAssets() external view returns (uint256) {
        uint256 assetInPool = _assetInPool(address(0));
        uint256 underlyingBalance = underlying.balanceOf(address(this));
        uint256 totalSupply_ = totalSupply();
        uint256 assetsWithIncome = assetInPool + underlyingBalance;
        if (assetsWithIncome < totalSupply_) {
            // If total assets with income is less than total supply, return 0
            return 0;
        } else {
            return assetsWithIncome - totalSupply_;
        }
    }

    function withdrawIncomeAssets(address asset, address to, uint256 amount) external nonReentrant onlyOwner {
        // Update interest to ensure exchange rate is fresh before calculations
        thirdPool.accrueInterest();
        uint256 assetInPool = _assetInPool(address(0));
        uint256 underlyingBalance = underlying.balanceOf(address(this));
        uint256 availableAmount = assetInPool + underlyingBalance - totalSupply();
        require(availableAmount >= amount, ERC4626TokenErrors.InsufficientIncomeAmount(availableAmount, amount));
        withdrawnIncomeAssets += amount;
        if (asset == address(underlying)) {
            _withdrawWithBuffer(address(underlying), to, amount);
        } else if (asset == address(thirdPool)) {
            uint256 shares = _convertUnderlyingToShare(amount);
            thirdPool.safeTransfer(to, shares);
        } else {
            revert ERC4626TokenErrors.InvalidToken();
        }
        emit ERC4626TokenEvents.WithdrawIncome(to, amount);
    }

    function updateBufferConfigAndAddReserves(uint256 additionalReserves, BufferConfig memory bufferConfig_)
        external
        onlyOwner
    {
        // Admin may add additional reserves when liquidity is low
        // to avoid the situation that the underlying liquidity is too low to withdraw
        underlying.safeTransferFrom(msg.sender, address(this), additionalReserves);
        _updateBufferConfig(bufferConfig_);
    }

    function _updateBufferConfig(BufferConfig memory bufferConfig_) internal {
        _checkBufferConfig(bufferConfig_.minimumBuffer, bufferConfig_.maximumBuffer, bufferConfig_.buffer);
        bufferConfig = BufferConfig(bufferConfig_.minimumBuffer, bufferConfig_.maximumBuffer, bufferConfig_.buffer);
        emit ERC4626TokenEvents.UpdateBufferConfig(
            bufferConfig_.minimumBuffer, bufferConfig_.maximumBuffer, bufferConfig_.buffer
        );
    }

    function _bufferConfig(address) internal view virtual override returns (BufferConfig memory) {
        return bufferConfig;
    }

    function _depositToPool(address assetAddr, uint256 amount) internal virtual override {
        IERC20(assetAddr).safeIncreaseAllowance(address(thirdPool), amount);
        uint256 err = thirdPool.mint(amount);
        if (err != 0) revert ERC4626TokenErrors.VenusMintFailed(err);
    }

    function _withdrawFromPool(address, address to, uint256 amount) internal virtual override {
        uint256 err = thirdPool.redeemUnderlying(amount);
        if (err != 0) revert ERC4626TokenErrors.VenusRedeemFailed(err);
        if (address(to) != address(this)) {
            underlying.safeTransfer(to, amount);
        }
    }

    function _assetInPool(address) internal view virtual override returns (uint256 amount) {
        uint256 shares = thirdPool.balanceOf(address(this));
        if (shares != 0) {
            amount = _convertShareToUnderlying(shares);
        }
    }

    function _convertShareToUnderlying(uint256 shares) internal view returns (uint256 amount) {
        // The exchange rate from shares to underlying
        // vToken exchangeRate is scaled by 1e18.
        // Formula: underlying = shares * exchangeRate / 1e18
        uint256 exchangeRateStored = thirdPool.exchangeRateStored();
        amount = shares.mulDiv(exchangeRateStored, PRECISION);
    }

    function _convertUnderlyingToShare(uint256 amount) internal view returns (uint256 shares) {
        // The exchange rate from shares to underlying
        // Formula: shares = underlying * 1e18 / exchangeRate
        uint256 exchangeRateStored = thirdPool.exchangeRateStored();
        shares = amount.mulDiv(PRECISION, exchangeRateStored);
    }
}
