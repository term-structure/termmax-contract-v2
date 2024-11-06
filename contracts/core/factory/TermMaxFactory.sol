// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IGearingToken, AggregatorV3Interface, IERC20Metadata, GearingTokenWithERC20} from "../tokens/GearingTokenWithERC20.sol";
import {MintableERC20, IMintableERC20} from "../tokens/MintableERC20.sol";
import {ITermMaxMarket} from "../TermMaxMarket.sol";
import {ITermMaxFactory} from "./ITermMaxFactory.sol";

contract TermMaxFactory is ITermMaxFactory, Ownable {
    error MarketImplementInitialized();
    error MarketImplementIsNotInitialized();
    error CantNotFindGtImplementation();

    event InitializeMarketImplement(address marketImplement);
    event SetGtImplementd(bytes32 key, address gtImplement);

    string constant PREFIX_FT = "FT:";
    string constant PREFIX_XT = "XT:";
    string constant PREFIX_LP_FT = "LpFT:";
    string constant PREFIX_LP_XT = "LpXT:";
    string constant PREFIX_GNFT = "GT:";
    string constant STRING_CONNECTION = "-";

    address public immutable tokenImplement;
    address public marketImplement;

    bytes32 public constant GT_ERC20 = keccak256("GearingTokenWithERC20");
    mapping(bytes32 => address) public gtImplements;

    constructor(address admin) Ownable(admin) {
        gtImplements[GT_ERC20] = address(new GearingTokenWithERC20());
        tokenImplement = address(new MintableERC20());
    }

    function initMarketImplement(address marketImplement_) external onlyOwner {
        if (marketImplement != address(0)) {
            revert MarketImplementInitialized();
        }
        marketImplement = marketImplement_;
        emit InitializeMarketImplement(marketImplement_);
    }

    function setGtImplement(
        bytes32 key,
        address gtImplement
    ) external onlyOwner {
        gtImplements[key] = gtImplement;
        emit SetGtImplementd(key, gtImplement);
    }

    function createMarket(
        DeployParams calldata deployParams
    ) external onlyOwner returns (address market) {
        if (marketImplement == address(0)) {
            revert MarketImplementIsNotInitialized();
        }
        address gtImplement = gtImplements[deployParams.gtKey];
        if (gtImplement == address(0)) {
            revert CantNotFindGtImplementation();
        }
        {
            // Deploy clone by implementation and salt
            market = Clones.cloneDeterministic(
                marketImplement,
                keccak256(
                    abi.encode(
                        deployParams.collateral,
                        deployParams.underlying,
                        deployParams.marketConfig.openTime,
                        deployParams.marketConfig.maturity,
                        deployParams.marketConfig.initialLtv
                    )
                )
            );
        }
        IGearingToken gt;
        IMintableERC20[4] memory tokens;
        {
            string memory collateralName = IERC20Metadata(
                deployParams.collateral
            ).name();
            string memory collateralSymbol = IERC20Metadata(
                deployParams.collateral
            ).symbol();

            uint8 decimals = deployParams.underlying.decimals();
            tokens = _deployTokens(
                market,
                collateralName,
                collateralSymbol,
                decimals
            );

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
                Clones.cloneDeterministic(
                    gtImplement,
                    keccak256(
                        abi.encode(
                            market,
                            deployParams.collateral,
                            deployParams.underlying
                        )
                    )
                )
            );
            gt.initialize(
                gtName,
                gtSymbol,
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
                deployParams.gtInitalParams
            );
        }

        ITermMaxMarket(market).initialize(
            deployParams.admin,
            address(deployParams.collateral),
            deployParams.underlying,
            tokens,
            gt,
            deployParams.marketConfig
        );
    }

    function _deployTokens(
        address market,
        string memory collateralName,
        string memory collateralSymbol,
        uint8 decimals
    ) internal returns (IMintableERC20[4] memory tokens) {
        {
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
    }

    function _deployMintableERC20(
        address market,
        string memory prefix,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal returns (IMintableERC20 token) {
        name = string(abi.encodePacked(prefix, name));
        symbol = string(abi.encodePacked(prefix, symbol));
        token = IMintableERC20(
            Clones.cloneDeterministic(
                tokenImplement,
                keccak256(abi.encode(market, name, symbol))
            )
        );
        token.initialize(market, name, symbol, decimals);
    }
}
