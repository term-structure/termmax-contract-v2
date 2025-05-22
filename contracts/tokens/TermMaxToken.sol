// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    OwnableUpgradeable,
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IAaveV3Minimal} from "contracts/extensions/aave/IAaveV3Minimal.sol";
import {TransferUtils} from "contracts/lib/TransferUtils.sol";
import {StakingBuffer} from "contracts/tokens/StakingBuffer.sol";
import {TermMaxTokenEvents} from "contracts/events/TermMaxTokenEvents.sol";
import {TermMaxTokenErrors} from "contracts/errors/TermMaxTokenErrors.sol";

contract TermMaxToken is
    StakingBuffer,
    ERC20Upgradeable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    TermMaxTokenEvents,
    TermMaxTokenErrors
{
    using TransferUtils for IERC20;

    IAaveV3Minimal public immutable aavePool;
    uint16 public immutable referralCode;

    IERC20 public aToken;
    IERC20 public underlying;
    BufferConfig public bufferConfig;
    /// @notice The token's decimals
    uint8 _decimals;
    uint256 internal withdawedIncomeAssets;

    constructor(address aavePool_, uint16 referralCode_) {
        aavePool = IAaveV3Minimal(aavePool_);
        referralCode = referralCode_;
        _disableInitializers();
    }

    function initialize(address admin, address underlying, BufferConfig memory bufferConfig_) public initializer {
        string memory name = string(abi.encodePacked("TermMax ", IERC20Metadata(underlying).name()));
        string memory symbol = string(abi.encodePacked("tmx", IERC20Metadata(underlying).symbol()));
        _decimals = IERC20Metadata(underlying).decimals();
        __ERC20_init(name, symbol);
        __Ownable_init(admin);
        __ReentrancyGuard_init();
        _updateBufferConfig(bufferConfig_);
        aToken = IERC20(aavePool.getReserveData(underlying).aTokenAddress);

        emit TermMaxTokenInitialized(admin, underlying);
    }

    function mint(address to, uint256 amount) external nonReentrant {
        _mint(to, amount);
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        _depositWithBuffer(address(underlying), amount);
    }

    function burn(address to, uint256 amount) external nonReentrant {
        _burn(msg.sender, amount);
        _withdrawWithBuffer(address(underlying), to, amount);
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
        require(avaliableAmount >= amount, InsufficientIncomeAmount(avaliableAmount, amount));
        withdawedIncomeAssets += amount;
        if (asset == address(underlying)) {
            _withdrawWithBuffer(address(underlying), to, amount);
        } else if (asset == address(aToken)) {
            aToken.safeTransfer(to, amount);
        } else {
            revert InvalidToken();
        }
        emit WithdrawIncome(to, amount);
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
        emit UpdateBufferConfig(bufferConfig_.minimumBuffer, bufferConfig_.maximumBuffer, bufferConfig_.buffer);
    }

    function decimals() public view override(ERC20Upgradeable) returns (uint8) {
        return _decimals;
    }

    function _bufferConfig(address) internal view virtual override returns (BufferConfig memory) {
        return bufferConfig;
    }

    function _depositToPool(address assetAddr, uint256 amount) internal virtual override {
        aavePool.supply(assetAddr, amount, address(this), referralCode);
    }

    function _withdrawFromPool(address assetAddr, address to, uint256 amount) internal virtual override {
        uint256 receivedAmount = aavePool.withdraw(assetAddr, amount, to);
        require(receivedAmount == amount, AaveWithdrawFailed(amount, receivedAmount));
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
