// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MintableERC20} from "./tokens/MintableERC20.sol";
import {GearingNft} from "./tokens/GearingNft.sol";
import "./AbstractTermMaxMarket.sol";

contract ERC20TermMaxMarket is AbstractTermMaxMarket {
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
                            GearingNft.initialize,
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
                            MintableERC20.initialize,
                            (name, symbol, decimals)
                        )
                    )
                )
            );
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override {}

    function getGNftInfo(
        uint256 nftId
    )
        external
        view
        override
        returns (address owner, uint128 debtAmt, bytes memory collateralData)
    {}

    function _transferCollateralFrom(
        address from,
        address to,
        address collateral,
        bytes memory collateralData
    ) internal virtual override {}

    function _transferCollateral(
        address to,
        address collateral,
        bytes memory collateralData
    ) internal virtual override {}

    function _sizeCollateralValue(
        bytes memory collateralData,
        IERC20 cash
    ) internal view virtual override returns (uint256) {}

    function _mergeLoanCollateral(
        bytes memory collateralDataA,
        bytes memory collateralDataB
    ) internal virtual override returns (bytes memory collateralData) {}

    function _deliveryCollateral(
        address collateral,
        uint256 ratio,
        address to
    ) internal virtual override returns (bytes memory deliveryData) {}
}
