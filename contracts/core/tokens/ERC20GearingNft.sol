// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./AbstractGearingNft.sol";

contract ERC20GearingNft is AbstractGearingNft {
    using SafeCast for uint256;
    using SafeCast for int256;

    struct ERC20GearingNftStorage {
        AggregatorV3Interface priceFeed;
    }

    bytes32 internal constant STORAGE_SLOT_ERC20_GEARING_NFT_STORAGE =
        bytes32(
            uint256(keccak256("TermMax.storage.ERC20GearingNftStorage")) - 1
        );

    function _getERC20GearingNftStorage()
        private
        pure
        returns (ERC20GearingNftStorage storage s)
    {
        bytes32 slot = STORAGE_SLOT_ERC20_GEARING_NFT_STORAGE;
        assembly {
            s.slot := slot
        }
    }

    function _authorizeUpgrade(address) internal virtual override onlyOwner {}

    function initialize(
        address market,
        string memory name,
        string memory symbol,
        IERC20 collateral,
        AggregatorV3Interface priceFeed,
        uint32 maxLtv,
        uint32 liquidationLtv
    ) public initializer {
        __ERC721_init(name, symbol);
        __Ownable_init(market);
        __AbstractGearingNft_init(address(collateral), maxLtv, liquidationLtv);
        _getERC20GearingNftStorage().priceFeed = priceFeed;
    }

    function delivery(
        uint256 ratio,
        address to
    )
        external
        override
        onlyOwner
        nonReentrant
        returns (bytes memory deliveryData)
    {
        IERC20 collateral = IERC20(_getGearingNftStorage().collateral);
        uint collateralReserve = collateral.balanceOf(address(this));
        uint amount = (collateralReserve * ratio) / Constants.DECIMAL_BASE;
        collateral.transfer(to, amount);
        deliveryData = abi.encode(amount);
    }

    function _mergeCollateral(
        bytes memory collateralDataA,
        bytes memory collateralDataB
    ) internal virtual override returns (bytes memory collateralData) {
        uint total = _decodeAmount(collateralDataA) +
            _decodeAmount(collateralDataB);
        collateralData = abi.encode(total);
    }

    function _transferCollateralFrom(
        address from,
        address to,
        bytes memory collateralData
    ) internal virtual override {
        IERC20(_getGearingNftStorage().collateral).transferFrom(
            from,
            to,
            _decodeAmount(collateralData)
        );
    }

    function _transferCollateral(
        address to,
        bytes memory collateralData
    ) internal virtual override {
        IERC20(_getGearingNftStorage().collateral).transfer(
            to,
            _decodeAmount(collateralData)
        );
    }

    function _sizeCollateralValue(
        bytes memory collateralData
    ) internal view virtual override returns (uint256 amount) {
        AggregatorV3Interface priceFeed = _getERC20GearingNftStorage()
            .priceFeed;
        uint decimals = 10 ** priceFeed.decimals();
        amount = _decodeAmount(collateralData);
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        amount = (answer.toUint256() * amount) / decimals;
    }

    function _decodeAmount(
        bytes memory collateralData
    ) internal pure returns (uint256) {
        return abi.decode(collateralData, (uint));
    }

    function _allocCollateral(
        address liquidator,
        address treasurer,
        uint256 collateralValue,
        LoanInfo memory loan
    ) internal virtual override {
        uint reward = (loan.debtAmt * Constants.REWARD_TO_LIQUIDATOR) /
            Constants.DECIMAL_BASE;
        uint rewardToProtocol = (loan.debtAmt * Constants.REWARD_TO_PROTOCOL) /
            Constants.DECIMAL_BASE;
        uint rewardToLiquidatorPlusDebt = reward + loan.debtAmt;

        if (rewardToLiquidatorPlusDebt >= collateralValue) {
            // Case 1: debt + reward >= collateralValue, send all colleteral to liquidator
            _transferCollateral(liquidator, loan.collateralData);
        } else if (
            rewardToLiquidatorPlusDebt + rewardToProtocol >= collateralValue
        ) {
            _transferCollateral(liquidator, loan.collateralData);
        } else {}
    }
}
