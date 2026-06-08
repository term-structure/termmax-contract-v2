// SPDX-License-Identifier:  BUSL-1.1
pragma solidity ^0.8.27;

import {
    ERC4626Upgradeable,
    Math,
    IERC4626
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    OwnableUpgradeable,
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {TransferUtilsV2} from "../lib/TransferUtilsV2.sol";
import {StakingBuffer} from "./StakingBuffer.sol";
import {ERC4626TokenEvents} from "../events/ERC4626TokenEvents.sol";
import {ERC4626TokenErrors} from "../errors/ERC4626TokenErrors.sol";

contract StableERC4626ForCustomize is
    StakingBuffer,
    ERC4626Upgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable
{
    using TransferUtilsV2 for *;

    /// @notice A customized third pool address
    /// @dev The assets will transfer to and from this pool during deposit and withdraw directly.
    ///      Make sure the pool is trustworthy and has asset allowance for this contract.
    ///      The pool should be an isolated pool only for this stable erc4626 token to avoid fund loss.
    address public thirdPool;
    IERC20 public underlying;
    BufferConfig public bufferConfig;
    uint256 internal withdawedIncomeAssets;

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address thirdPool_, address underlying_, BufferConfig memory bufferConfig_)
        public
        initializer
    {
        thirdPool = thirdPool_;
        underlying = IERC20(underlying_);
        string memory name =
            string(abi.encodePacked("TermMax Stable CustomizeERC4626 ", IERC20Metadata(underlying_).name()));
        string memory symbol = string(abi.encodePacked("tmsc", IERC20Metadata(underlying_).symbol()));
        __ERC20_init_unchained(name, symbol);
        __Ownable_init_unchained(admin);
        __ERC4626_init_unchained(IERC20(underlying_));
        __ReentrancyGuard_init_unchained();
        _updateBufferConfig(bufferConfig_);

        emit ERC4626TokenEvents.ERC4626ForCustomizeInitialized(admin, underlying_, thirdPool_);
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
        IERC20 _underlying = IERC20(asset());
        uint256 assetInPool = _assetInPool(address(_underlying));
        uint256 underlyingBalance = _underlying.balanceOf(address(this));
        uint256 totalSupply_ = totalSupply();
        uint256 assetsWithIncome = assetInPool + underlyingBalance + withdawedIncomeAssets;
        if (assetsWithIncome < totalSupply_) {
            // If total assets with income is less than total supply, return 0
            return 0;
        } else {
            return assetsWithIncome - totalSupply_;
        }
    }

    function currentIncomeAssets() external view returns (uint256) {
        IERC20 _underlying = IERC20(asset());
        uint256 assetInPool = _assetInPool(address(_underlying));
        uint256 underlyingBalance = _underlying.balanceOf(address(this));
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
        uint256 assetInPool = _assetInPool(address(underlying));
        uint256 underlyingBalance = underlying.balanceOf(address(this));
        uint256 avaliableAmount = assetInPool + underlyingBalance - totalSupply();
        require(avaliableAmount >= amount, ERC4626TokenErrors.InsufficientIncomeAmount(avaliableAmount, amount));
        withdawedIncomeAssets += amount;
        if (asset == address(underlying)) {
            _withdrawWithBuffer(address(underlying), to, amount);
        } else {
            revert ERC4626TokenErrors.InvalidToken();
        }
        emit ERC4626TokenEvents.WithdrawIncome(to, amount);
    }

    function withdrawAssets(IERC20 token, address recipient, uint256 amount) external nonReentrant onlyOwner {
        require(address(token) != address(underlying) && address(token) != thirdPool, ERC4626TokenErrors.InvalidToken());
        token.safeTransfer(recipient, amount);
        emit ERC4626TokenEvents.WithdrawAssets(token, _msgSender(), recipient, amount);
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
        IERC20(assetAddr).safeTransfer(thirdPool, amount);
    }

    function _withdrawFromPool(address assetAddr, address to, uint256 amount) internal virtual override {
        IERC20(assetAddr).safeTransferFrom(thirdPool, to, amount);
    }

    function _assetInPool(address assetAddr) internal view virtual override returns (uint256 amount) {
        amount = IERC20(assetAddr).balanceOf(thirdPool);
    }
}
