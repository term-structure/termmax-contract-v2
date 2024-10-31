// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./AbstractGearingNft.sol";

contract ERC20GearingNft is AbstractGearingNft {
    using SafeCast for uint256;
    using SafeCast for int256;

    struct ERC20GearingNftStorage {
        AggregatorV3Interface collateralOracle;
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
        string memory name,
        string memory symbol,
        address admin,
        GtConfig memory config,
        AggregatorV3Interface collateralOracle
    ) public initializer {
        __AbstractGearingNft_init(name, symbol, admin, config);
        _getERC20GearingNftStorage().collateralOracle = collateralOracle;
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
        IERC20 collateral = IERC20(_getGearingNftStorage().config.collateral);
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
        IERC20(_getGearingNftStorage().config.collateral).transferFrom(
            from,
            to,
            _decodeAmount(collateralData)
        );
    }

    function _transferCollateral(
        address to,
        bytes memory collateralData
    ) internal virtual override {
        IERC20(_getGearingNftStorage().config.collateral).transfer(
            to,
            _decodeAmount(collateralData)
        );
    }

    function _getCollateralValue(
        bytes memory collateralData
    ) internal view virtual override returns (uint256 amount) {
        AggregatorV3Interface collateralOracle = _getERC20GearingNftStorage()
            .collateralOracle;
        uint decimals = 10 ** collateralOracle.decimals();
        amount = _decodeAmount(collateralData);
        (, int256 answer, , , ) = collateralOracle.latestRoundData();
        amount = (answer.toUint256() * amount) / decimals;
    }

    function _decodeAmount(
        bytes memory collateralData
    ) internal pure returns (uint256) {
        return abi.decode(collateralData, (uint));
    }

    function _removeCollateral(
        LoanInfo memory loan,
        bytes memory collateralData
    ) internal virtual override returns (bytes memory) {
        uint amount = _decodeAmount(loan.collateralData) -
            _decodeAmount(collateralData);
        return abi.encode(amount);
    }

    function _addCollateral(
        LoanInfo memory loan,
        bytes memory collateralData
    ) internal virtual override returns (bytes memory) {
        uint amount = _decodeAmount(loan.collateralData) +
            _decodeAmount(collateralData);
        return abi.encode(amount);
    }

    // function _liquidate(
    //     LoanInfo memory loan,
    //     address liquidator,
    //     address treasurer,
    //     uint128 repayAmt,
    //     uint256 collateralValue
    // ) internal virtual override returns (bytes memory collateralData) {
    //     uint rewardToLiquidator = (repayAmt * Constants.REWARD_TO_LIQUIDATOR) /
    //         Constants.DECIMAL_BASE;
    //     uint rewardToProtocol = (repayAmt * Constants.REWARD_TO_PROTOCOL) /
    //         Constants.DECIMAL_BASE;
    //     uint rewardToLiquidatorPlusRepayAmt = rewardToLiquidator + repayAmt;
    //     uint amount = _decodeAmount(loan.collateralData);
    //     uint price = (collateralValue * Constants.DECIMAL_BASE) / amount;
    //     IERC20 collateral = IERC20(_getGearingNftStorage().collateral);
    //     if (rewardToLiquidatorPlusRepayAmt >= collateralValue) {
    //         // Case 1: repayAmt + rewardToLiquidator >= collateralValue, send all colleteral to liquidator

    //         collateral.transfer(liquidator, amount);
    //     } else if (
    //         rewardToLiquidatorPlusRepayAmt + rewardToProtocol >= collateralValue
    //     ) {
    //         // Case 2: repayAmt + rewardToLiquidator + rewardToProtocol >= collateralValue
    //         // uint collateralToLiquidator = rewardToLiquidatorPlusRepayAmt * Constants.DECIMAL_BASE_SQRT/ price/Constants.DECIMAL_BASE;
    //         // collateral.transfer(liquidator,collateralToLiquidator );
    //         // uint collateralToLiquidator
    //     } else {
    //         _transferCollateral(liquidator, loan.collateralData);
    //     }
    // }

    function _liquidate(
        GtConfig memory config,
        LoanInfo memory loan,
        address liquidator,
        address treasurer,
        uint128 repayAmt,
        uint256 collateralValue,
        uint256 debtValue
    ) internal virtual override returns (bytes memory collateralData) {}
}
