// SPDX-License-Identifier:  BUSL-1.1
pragma solidity ^0.8.27;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    OwnableUpgradeable,
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IAaveV3Pool} from "../extensions/aave/IAaveV3Pool.sol";
import {TransferUtilsV2} from "../lib/TransferUtilsV2.sol";
import {StakingBuffer} from "./StakingBuffer.sol";
import {ERC4626TokenEvents} from "../events/ERC4626TokenEvents.sol";
import {ERC4626TokenErrors} from "../errors/ERC4626TokenErrors.sol";

contract VariableERC4626ForAave is
    StakingBuffer,
    ERC4626Upgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable
{
    using TransferUtilsV2 for IERC20;

    IAaveV3Pool public immutable aavePool;
    uint16 public immutable referralCode;

    IERC20 public aToken;
    IERC20 public underlying;
    BufferConfig public bufferConfig;

    constructor(address aavePool_, uint16 referralCode_) {
        aavePool = IAaveV3Pool(aavePool_);
        referralCode = referralCode_;
        _disableInitializers();
    }

    function initialize(address admin, address underlying_, BufferConfig memory bufferConfig_) public initializer {
        underlying = IERC20(underlying_);
        string memory name =
            string(abi.encodePacked("TermMax Variable AaveERC4626 ", IERC20Metadata(underlying_).name()));
        string memory symbol = string(abi.encodePacked("tmva", IERC20Metadata(underlying_).symbol()));
        __ERC20_init_unchained(name, symbol);
        __ERC4626_init_unchained(IERC20(underlying_));
        __Ownable_init_unchained(admin);
        __ReentrancyGuard_init_unchained();
        _updateBufferConfig(bufferConfig_);
        aToken = IERC20(aavePool.getReserveData(underlying_).aTokenAddress);

        emit ERC4626TokenEvents.ERC4626ForAaveInitialized(admin, underlying_, false);
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + _assetInPool(address(underlying));
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

    function updateBufferConfig(BufferConfig memory bufferConfig_) external onlyOwner {
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
        IERC20(assetAddr).safeIncreaseAllowance(address(aavePool), amount);
        aavePool.supply(assetAddr, amount, address(this), referralCode);
    }

    function _withdrawFromPool(address assetAddr, address to, uint256 amount) internal virtual override {
        aToken.safeIncreaseAllowance(address(aavePool), amount);
        uint256 receivedAmount = aavePool.withdraw(assetAddr, amount, to);
        require(receivedAmount == amount, ERC4626TokenErrors.AaveWithdrawFailed(amount, receivedAmount));
    }

    function _assetInPool(address) internal view virtual override returns (uint256 amount) {
        amount = aToken.balanceOf(address(this));
    }
}
