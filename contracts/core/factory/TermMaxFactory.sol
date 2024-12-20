// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IGearingToken, IOracle, IERC20Metadata, GearingTokenWithERC20} from "../tokens/GearingTokenWithERC20.sol";
import {MintableERC20, IMintableERC20} from "../tokens/MintableERC20.sol";
import {ITermMaxTokenPair} from "../ITermMaxTokenPair.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxFactory} from "./ITermMaxFactory.sol";

/**
 * @title The TermMax factory
 * @author Term Structure Labs
 */
contract TermMaxFactory is ITermMaxFactory, Ownable {
    string constant PREFIX_FT = "FT:";
    string constant PREFIX_XT = "XT:";
    string constant PREFIX_LP_FT = "LpFT:";
    string constant PREFIX_LP_XT = "LpXT:";
    string constant PREFIX_GNFT = "GT:";
    string constant STRING_CONNECTION = "-";

    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

    /// @notice The implementation of TermMax ERC20 Token contract
    address public immutable tokenImplement;

    /// @notice The implementation of TermMax Token Pair contract
    address public tokenPairImplement;

    /// @notice The implementation of TermMax Market contract
    address public marketImplement;

    /// @notice The implementations of TermMax Gearing Token contract
    /// @dev Based on the abstract GearingToken contract,
    ///      different GearingTokens can be adapted to various collaterals,
    ///      such as ERC20 tokens and ERC721 tokens.
    mapping(bytes32 => address) public gtImplements;

    constructor(address admin) Ownable(admin) {
        gtImplements[GT_ERC20] = address(new GearingTokenWithERC20());
        tokenImplement = address(new MintableERC20());
    }

    /// @notice Initialize the implementation of TermMax Token Pair contract
    function initTokenPairImplement(address marketImplement_) external onlyOwner {
        if (marketImplement != address(0)) {
            revert TokenPairImplementInitialized();
        }
        marketImplement = marketImplement_;
        emit InitializeTokenPairImplement(marketImplement_);
    }

    /// @notice Initialize the implementation of TermMax Market contract
    function initMarketImplement(address marketImplement_) external onlyOwner {
        if (marketImplement != address(0)) {
            revert MarketImplementInitialized();
        }
        marketImplement = marketImplement_;
        emit InitializeMarketImplement(marketImplement_);
    }

    /**
     * @inheritdoc ITermMaxFactory
     */
    function setGtImplement(
        string memory gtImplementName,
        address gtImplement
    ) external override onlyOwner {
        bytes32 key = keccak256(abi.encodePacked(gtImplementName));
        gtImplements[key] = gtImplement;
        emit SetGtImplement(key, gtImplement);
    }

    /**
     * @inheritdoc ITermMaxFactory
     */
    function predictTokenPairAddress(
        IERC20Metadata collateral,
        IERC20Metadata underlying,
        uint maturity
    ) external view override returns (address tokenPair) {
        return
            Clones.predictDeterministicAddress(
                tokenPairImplement,
                keccak256(
                    abi.encode(
                        collateral,
                        underlying,
                        maturity
                    )
                )
            );
    }

    /**
     * @inheritdoc ITermMaxFactory
     */
    function createTokenPair(
        TokenPairDeployParams calldata deployParams
    ) external override onlyOwner returns (address tokenPair) {
        if (tokenPairImplement == address(0)) {
            revert TokenPairImplementIsNotInitialized();
        }
        address gtImplement = gtImplements[deployParams.gtKey];
        if (gtImplement == address(0)) {
            revert CantNotFindGtImplementation();
        }
        {
            // Deploy clone by implementation and salt
            tokenPair = Clones.cloneDeterministic(
                tokenPairImplement,
                keccak256(
                    abi.encode(
                        deployParams.collateral,
                        deployParams.underlying,
                        deployParams.tokenPairConfig.maturity
                    )
                )
            );
        }
        IGearingToken gt;
        IMintableERC20 ft;
        IMintableERC20 xt;
        {
            string memory name = string(
                abi.encodePacked(
                    IERC20Metadata(deployParams.collateral).name(),
                    STRING_CONNECTION,
                    deployParams.underlying.name()
                )
            );
            string memory symbol = string(
                abi.encodePacked(
                    IERC20Metadata(deployParams.collateral).symbol(),
                    STRING_CONNECTION,
                    deployParams.underlying.symbol()
                )
            );

            uint8 decimals = deployParams.underlying.decimals();
            (ft, xt) = _deployTokens(tokenPair, name, symbol, decimals);

            string memory gtName = string(abi.encodePacked(PREFIX_GNFT, name));
            string memory gtSymbol = string(
                abi.encodePacked(PREFIX_GNFT, symbol)
            );
            gt = IGearingToken(
                Clones.cloneDeterministic(
                    gtImplement,
                    keccak256(
                        abi.encode(
                            tokenPair,
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
                    tokenPair: address(tokenPair),
                    collateral: address(deployParams.collateral),
                    underlying: deployParams.underlying,
                    ft: ft,
                    treasurer: deployParams.tokenPairConfig.treasurer,
                    oracle: deployParams.oracle,
                    maturity: deployParams.tokenPairConfig.maturity,
                    liquidationLtv: deployParams.liquidationLtv,
                    maxLtv: deployParams.maxLtv,
                    liquidatable: deployParams.liquidatable
                }),
                deployParams.gtInitalParams
            );
        }

        ITermMaxTokenPair(tokenPair).initialize(
            deployParams.admin,
            address(deployParams.collateral),
            deployParams.underlying,
            ft,
            xt,
            gt,
            deployParams.tokenPairConfig
        );
    }

    /**
     * @inheritdoc ITermMaxFactory
     */
    function predictMarketAddress(
        ITermMaxTokenPair tokenPair,
        address maker
    ) external view override returns (address market) {
        return
            Clones.predictDeterministicAddress(
                marketImplement,
                keccak256(
                    abi.encode(
                        tokenPair,
                        maker
                    )
                )
            );
    }

    /**
     * @inheritdoc ITermMaxFactory
     */
    function createMarket(
        MarketDeployParams calldata deployParams
    ) external override onlyOwner returns (address market) {
        if (marketImplement == address(0)) {
            revert MarketImplementIsNotInitialized();
        }
        {
            // Deploy clone by implementation and salt
            market = Clones.cloneDeterministic(
                marketImplement,
                keccak256(
                    abi.encode(
                        deployParams.tokenPair,
                        deployParams.marketConfig.maker
                    )
                )
            );
        }
        ITermMaxMarket(market).initialize(
            deployParams.admin,
            deployParams.tokenPair,
            deployParams.marketConfig
        );
    }

    function _deployTokens(
        address market,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal returns (IMintableERC20 ft, IMintableERC20 xt) {
        {
            // Deploy tokens
            ft = _deployMintableERC20(
                address(market),
                PREFIX_FT,
                name,
                symbol,
                decimals
            );
            xt = _deployMintableERC20(
                address(market),
                PREFIX_XT,
                name,
                symbol,
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
