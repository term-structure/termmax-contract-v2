// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20GearingToken, IGearingToken, AggregatorV3Interface} from "../tokens/ERC20GearingToken.sol";
import {MintableERC20, IMintableERC20} from "../tokens/MintableERC20.sol";
import {ITermMaxMarket} from "../TermMaxMarket.sol";
import {ITermMaxFactory} from "./ITermMaxFactory.sol";

contract TermMaxFactory is ITermMaxFactory, Ownable {
    string constant PREFIX_FT = "FT:";
    string constant PREFIX_XT = "XT:";
    string constant PREFIX_LP_FT = "LpFT:";
    string constant PREFIX_LP_XT = "LpXT:";
    string constant PREFIX_GNFT = "GT:";
    string constant STRING_CONNECTION = "-";

    ERC20GearingToken immutable gtImplement;
    MintableERC20 immutable tokenImplement;

    bytes marketBytes;

    constructor(address admin) Ownable(admin) {
        gtImplement = new ERC20GearingToken();
        tokenImplement = new MintableERC20();
    }

    function initMarketBytes(bytes memory marketBytes_) external onlyOwner {
        if (marketBytes.length != 0) {
            revert();
        }
        marketBytes = marketBytes_;
    }

    function createERC20Market(
        DeployParams calldata deployParams
    ) external override onlyOwner returns (address market) {
        if (marketBytes.length == 0) {
            revert();
        }
        bytes memory initCode = abi.encodePacked(
            marketBytes,
            abi.encode(
                address(deployParams.collateral),
                deployParams.underlying,
                deployParams.marketConfig.openTime,
                deployParams.marketConfig.maturity
            )
        );
        assembly {
            market := create2(0, add(initCode, 0x20), mload(initCode), 0)
        }
        (IMintableERC20[4] memory tokens, IGearingToken gt) = _deployTokens(
            market,
            deployParams
        );
        ITermMaxMarket(market).initialize(
            tokens,
            gt,
            deployParams.marketConfig
        );
        Ownable(market).transferOwnership(deployParams.admin);
    }

    function _deployTokens(
        address market,
        ITermMaxFactory.DeployParams memory deployParams
    ) internal returns (IMintableERC20[4] memory tokens, IGearingToken gt) {
        string memory collateralName = deployParams.collateral.name();
        string memory collateralSymbol = deployParams.collateral.symbol();
        {
            uint8 decimals = deployParams.underlying.decimals();
            // Deploy tokens

            tokens[0] = _deployMintableERC20(
                address(market),
                PREFIX_FT,
                collateralName,
                collateralSymbol,
                decimals
            );
            tokens[1] = _deployMintableERC20(
                address(market),
                PREFIX_XT,
                collateralName,
                collateralSymbol,
                decimals
            );
            tokens[2] = _deployMintableERC20(
                address(market),
                PREFIX_LP_FT,
                collateralName,
                collateralSymbol,
                decimals
            );
            tokens[3] = _deployMintableERC20(
                address(market),
                PREFIX_LP_XT,
                collateralName,
                collateralSymbol,
                decimals
            );
        }

        string memory gtName = string(
            abi.encodePacked(
                PREFIX_GNFT,
                deployParams.underlying.name(),
                STRING_CONNECTION,
                collateralName
            )
        );
        string memory gtSymbol = string(
            abi.encodePacked(
                PREFIX_GNFT,
                deployParams.underlying.symbol(),
                STRING_CONNECTION,
                collateralSymbol
            )
        );
        gt = IGearingToken(
            address(
                new ERC1967Proxy(
                    address(gtImplement),
                    abi.encodeCall(
                        ERC20GearingToken.initialize,
                        (
                            gtName,
                            gtSymbol,
                            deployParams.admin,
                            IGearingToken.GtConfig({
                                market: address(market),
                                collateral: address(deployParams.collateral),
                                underlying: deployParams.underlying,
                                ft: tokens[0],
                                treasurer: deployParams.marketConfig.treasurer,
                                underlyingOracle: deployParams.underlyingOracle,
                                maturity: deployParams.marketConfig.maturity,
                                liquidationLtv: deployParams.liquidationLtv,
                                maxLtv: deployParams.maxLtv,
                                liquidatable: deployParams.liquidatable
                            }),
                            deployParams.collateralOracle
                        )
                    )
                )
            )
        );
    }

    function _deployMintableERC20(
        address market,
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
                        address(tokenImplement),
                        abi.encodeCall(
                            MintableERC20.initialize,
                            (market, name, symbol, decimals)
                        )
                    )
                )
            );
    }
}
