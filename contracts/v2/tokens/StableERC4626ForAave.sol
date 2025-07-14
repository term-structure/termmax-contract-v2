// SPDX-License-Identifier:  BUSL-1.1
pragma solidity ^0.8.27;

import {ERC4626Upgradeable, Math} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    OwnableUpgradeable,
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IAaveV3Minimal} from "../extensions/aave/IAaveV3Minimal.sol";
import {TransferUtilsV2} from "../lib/TransferUtilsV2.sol";
import {StakingBuffer} from "./StakingBuffer.sol";
import {PendingLib, PendingAddress} from "../../v1/lib/PendingLib.sol";
import {ERC4626ForAaveEvents} from "../events/ERC4626ForAaveEvents.sol";
import {ERC4626ForAaveErrors} from "../errors/ERC4626ForAaveErrors.sol";

contract StableERC4626ForAave is
    StakingBuffer,
    ERC4626Upgradeable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using TransferUtilsV2 for IERC20;
    using PendingLib for PendingAddress;

    IAaveV3Minimal public immutable aavePool;
    uint16 public immutable referralCode;

    IERC20 public aToken;
    IERC20 public underlying;
    BufferConfig public bufferConfig;
    /// @notice The token's decimals
    uint8 _decimals;
    uint256 internal withdawedIncomeAssets;

    /// @notice The timelock period for upgrade operations (in seconds)
    uint256 public constant UPGRADE_TIMELOCK = 1 days;

    /// @notice Pending upgrade implementation address with timelock
    PendingAddress internal _pendingImplementation;

    constructor(address aavePool_, uint16 referralCode_) {
        aavePool = IAaveV3Minimal(aavePool_);
        referralCode = referralCode_;
        _disableInitializers();
    }

    function initialize(address admin, address underlying_, BufferConfig memory bufferConfig_) public initializer {
        underlying = IERC20(underlying_);
        string memory name = string(abi.encodePacked("TermMax Stable AaveERC4626 ", IERC20Metadata(underlying_).name()));
        string memory symbol = string(abi.encodePacked("tmsa", IERC20Metadata(underlying_).symbol()));
        _decimals = IERC20Metadata(underlying_).decimals();
        __ERC20_init_unchained(name, symbol);
        __ERC4626_init_unchained(IERC20(underlying_));
        __Ownable_init_unchained(admin);
        __ReentrancyGuard_init();
        _updateBufferConfig(bufferConfig_);
        aToken = IERC20(aavePool.getReserveData(underlying_).aTokenAddress);

        emit ERC4626ForAaveEvents.ERC4626ForAaveInitialized(admin, underlying_, true);
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
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
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

    function burnToAToken(address to, uint256 amount) external nonReentrant {
        _burn(msg.sender, amount);
        aToken.safeTransfer(to, amount);
    }

    function totalIncomeAssets() external view returns (uint256) {
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        uint256 underlyingBalance = underlying.balanceOf(address(this));
        return aTokenBalance + underlyingBalance - totalSupply() + withdawedIncomeAssets;
    }

    function withdrawIncomeAssets(address asset, address to, uint256 amount) external nonReentrant onlyOwner {
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        uint256 underlyingBalance = underlying.balanceOf(address(this));
        uint256 avaliableAmount = aTokenBalance + underlyingBalance - totalSupply();
        require(avaliableAmount >= amount, ERC4626ForAaveErrors.InsufficientIncomeAmount(avaliableAmount, amount));
        withdawedIncomeAssets += amount;
        if (asset == address(underlying)) {
            _withdrawWithBuffer(address(underlying), to, amount);
        } else if (asset == address(aToken)) {
            aToken.safeTransfer(to, amount);
        } else {
            revert ERC4626ForAaveErrors.InvalidToken();
        }
        emit ERC4626ForAaveEvents.WithdrawIncome(to, amount);
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
        emit ERC4626ForAaveEvents.UpdateBufferConfig(bufferConfig_.minimumBuffer, bufferConfig_.maximumBuffer, bufferConfig_.buffer);
    }

    function _bufferConfig(address) internal view virtual override returns (BufferConfig memory) {
        return bufferConfig;
    }

    function _depositToPool(address assetAddr, uint256 amount) internal virtual override {
        IERC20(assetAddr).safeIncreaseAllowance(address(aavePool), amount);
        aavePool.supply(assetAddr, amount, address(this), referralCode);
    }

    function _withdrawFromPool(address assetAddr, address to, uint256 amount) internal virtual override {
        aToken.safeIncreaseAllowance(address(aavePool), amount);
        uint256 receivedAmount = aavePool.withdraw(assetAddr, amount, to);
        require(receivedAmount == amount, ERC4626ForAaveErrors.AaveWithdrawFailed(amount, receivedAmount));
    }

    function _assetInPool(address) internal view virtual override returns (uint256 amount) {
        amount = aToken.balanceOf(address(this));
    }

    /// @notice Submit a new implementation for upgrade with timelock
    /// @param newImplementation The address of the new implementation contract
    function submitPendingUpgrade(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert ERC4626ForAaveErrors.InvalidImplementation();
        if (_pendingImplementation.validAt != 0) revert ERC4626ForAaveErrors.AlreadyPending();

        _pendingImplementation.update(newImplementation, UPGRADE_TIMELOCK);

        emit ERC4626ForAaveEvents.SubmitUpgrade(newImplementation, _pendingImplementation.validAt);
    }

    /// @notice Revoke the pending implementation upgrade
    function revokeUpgrade() external onlyOwner {
        if (_pendingImplementation.validAt == 0) revert ERC4626ForAaveErrors.NoPendingValue();

        delete _pendingImplementation;

        emit ERC4626ForAaveEvents.RevokeUpgrade(msg.sender);
    }

    /// @notice Get the pending implementation upgrade details
    /// @return implementation The pending implementation address
    /// @return validAt The timestamp when the upgrade becomes valid
    function pendingImplementation() external view returns (address implementation, uint64 validAt) {
        return (_pendingImplementation.value, _pendingImplementation.validAt);
    }

    /// @notice Override _authorizeUpgrade to prevent direct upgrades without timelock
    /// @dev This function should never allow upgrades as they must go through the timelock process
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {
        if (_pendingImplementation.validAt == 0) revert ERC4626ForAaveErrors.NoPendingValue();
        if (newImplementation != _pendingImplementation.value) revert ERC4626ForAaveErrors.InvalidImplementation();
        if (block.timestamp < _pendingImplementation.validAt) revert ERC4626ForAaveErrors.TimelockNotElapsed();
        delete _pendingImplementation;
        emit ERC4626ForAaveEvents.AcceptUpgrade(msg.sender, newImplementation);
    }
}
