// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    IERC4626,
    IERC20,
    ERC4626Upgradeable,
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {TransferUtils} from "contracts/lib/TransferUtils.sol";
import {IAaveV3Minimal} from "./IAaveV3Minimal.sol";
import {StakingBuffer} from "contracts/extensions/StakingBuffer.sol";

contract AaveVault is ERC4626Upgradeable, StakingBuffer, ReentrancyGuardUpgradeable {
    using TransferUtils for address;

    IERC20 public aToken;
    IAaveV3Minimal public aavePool;
    uint16 public referralCode;

    function initialize(
        string memory name_,
        string memory symbol_,
        address underlyingAsset_,
        address aavePool_,
        uint16 referralCode_
    ) external initializer {
        __ERC20_init(name_, symbol_);
        __ERC4626_init(IERC20(underlyingAsset_));
        __ReentrancyGuard_init();

        aavePool = IAaveV3Minimal(aavePool_);
        aToken = IERC20(aavePool.getReserveData(underlyingAsset_).aTokenAddress);
        referralCode = referralCode_;
    }

    function totalAssets() public view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        TransferUtils.safeTransferFrom(IERC20(asset()), caller, address(this), assets);
        _mint(receiver, shares);
        _depositWithBuffer(asset(), assets);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        _withdrawWithBuffer(asset(), assets);
        TransferUtils.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _bufferConfig(address assertAddr) internal view virtual override returns (BufferConfig memory) {}

    function _depositToPool(address assertAddr, uint256 amount) internal virtual override {
        aavePool.supply(assertAddr, amount, address(this), referralCode);
    }

    function _withdrawFromPool(address assertAddr, uint256 amount) internal virtual override {
        aavePool.withdraw(assertAddr, amount, address(this));
    }
}
