// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./AbstractTermMaxMarket.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract ERC20TermMaxMarket is AbstractTermMaxMarket {
    using SafeCast for uint256;
    using SafeCast for int256;

    error UnallowedUpgrade();

    struct ERC20TermMaxMarketStorage {
        AggregatorV3Interface priceFeed;
    }

    bytes32 internal constant STORAGE_SLOT_ERC20_MARKET_STORAGE =
        bytes32(uint256(keccak256("TermMax.storage.ERC20TermMaxMarket")) - 1);

    function _getERC20MarketStorage()
        private
        pure
        returns (ERC20TermMaxMarketStorage storage s)
    {
        bytes32 slot = STORAGE_SLOT_ERC20_MARKET_STORAGE;
        assembly {
            s.slot := slot
        }
    }

    function initialize(
        IERC20Metadata collateral,
        IERC20 cash,
        uint64 openTime,
        uint64 maturity,
        address mintableErc20Implement,
        address gearingNftImplement
    ) public initializer {
        if (
            openTime < block.timestamp ||
            maturity < block.timestamp + TermMaxCurve.SECONDS_IN_MOUNTH
        ) {
            revert InvalidTime(openTime, maturity);
        }
        if (address(collateral) == address(cash)) {
            revert CollateralCanNotEqualCash();
        }
        TermMaxStorage.MarketTokens storage tokens = TermMaxStorage
            ._getTokens();
        {
            IERC20Metadata cashMertaData = IERC20Metadata(address(cash));
            uint8 decimals = cashMertaData.decimals();
            // Deploy tokens
            tokens.collateralToken = address(collateral);
            tokens.cash = cash;
            string memory collateralName = collateral.name();
            string memory collateralSymbol = collateral.symbol();
            tokens.ft = _deployMintableERC20(
                mintableErc20Implement,
                PREFIX_FT,
                collateralName,
                collateralSymbol,
                decimals
            );
            tokens.xt = _deployMintableERC20(
                mintableErc20Implement,
                PREFIX_XT,
                collateralName,
                collateralSymbol,
                decimals
            );
            tokens.lpFt = _deployMintableERC20(
                mintableErc20Implement,
                PREFIX_LP_FT,
                collateralName,
                collateralSymbol,
                decimals
            );
            tokens.lpXt = _deployMintableERC20(
                mintableErc20Implement,
                PREFIX_LP_XT,
                collateralName,
                collateralSymbol,
                decimals
            );
            string memory nftName = string(
                abi.encodePacked(
                    PREFIX_GNFT,
                    cashMertaData.name(),
                    STRING_UNDER_LINE,
                    collateralName
                )
            );
            string memory nftSymbol = string(
                abi.encodePacked(
                    PREFIX_GNFT,
                    cashMertaData.symbol(),
                    STRING_UNDER_LINE,
                    collateralSymbol
                )
            );
            tokens.gNft = IGearingNft(
                address(
                    new ERC1967Proxy(
                        address(gearingNftImplement),
                        abi.encodeCall(
                            IGearingNft.initialize,
                            (nftName, nftSymbol)
                        )
                    )
                )
            );
        }
        IMintableERC20[4] memory erc20Tokens = [
            tokens.ft,
            tokens.xt,
            tokens.lpFt,
            tokens.lpXt
        ];
        emit MarketDeployed(
            msg.sender,
            address(collateral),
            cash,
            openTime,
            maturity,
            erc20Tokens,
            tokens.gNft
        );
    }

    function _deployMintableERC20(
        address implement,
        string memory prefix,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal returns (IMintableERC20) {
        name = string(abi.encodePacked(prefix, name));
        symbol = string(abi.encodePacked(prefix, symbol));
        return
            IMintableERC20(
                address(
                    new ERC1967Proxy(
                        address(implement),
                        abi.encodeCall(
                            IMintableERC20.initialize,
                            (name, symbol, decimals)
                        )
                    )
                )
            );
    }

    function _authorizeUpgrade(address) internal virtual override {
        revert UnallowedUpgrade();
    }

    function getGNftInfo(
        uint256 nftId
    )
        external
        view
        override
        returns (
            address owner,
            uint128 debtAmt,
            uint128 health,
            bytes memory collateralData
        )
    {
        (owner, debtAmt, collateralData) = TermMaxStorage
            ._getTokens()
            .gNft
            .loanInfo(nftId);
        health = _calcHealth(debtAmt, collateralData).toUint128();
    }

    function _decodeAmount(
        bytes memory collateralData
    ) internal pure returns (uint256) {
        return abi.decode(collateralData, (uint));
    }

    function _transferCollateralFrom(
        address from,
        address to,
        address collateral,
        bytes memory collateralData
    ) internal virtual override {
        IERC20(collateral).transferFrom(
            from,
            to,
            _decodeAmount(collateralData)
        );
    }

    function _transferCollateral(
        address to,
        address collateral,
        bytes memory collateralData
    ) internal virtual override {
        IERC20(collateral).transfer(to, _decodeAmount(collateralData));
    }

    function _sizeCollateralValue(
        bytes memory collateralData
    ) internal view virtual override returns (uint256 amount) {
        uint decimals = 10 **
            IERC20Metadata(TermMaxStorage._getTokens().collateralToken)
                .decimals();
        amount = _decodeAmount(collateralData);
        (, int256 answer, , , ) = _getERC20MarketStorage()
            .priceFeed
            .latestRoundData();
        amount = (answer.toUint256() * amount) / decimals;
    }

    function _mergeLoanCollateral(
        bytes memory collateralDataA,
        bytes memory collateralDataB
    ) internal virtual override returns (bytes memory collateralData) {
        uint total = _decodeAmount(collateralDataA) +
            _decodeAmount(collateralDataB);
        collateralData = abi.encode(total);
    }

    function _deliveryCollateral(
        address collateralToken,
        uint256 ratio,
        address to
    ) internal virtual override returns (bytes memory deliveryData) {
        uint collateralReserve = IERC20(collateralToken).balanceOf(
            address(this)
        );
        uint amount = (collateralReserve * ratio) / TermMaxCurve.DECIMAL_BASE;
        IERC20(collateralToken).transfer(to, amount);
        deliveryData = abi.encode(amount);
    }
}
