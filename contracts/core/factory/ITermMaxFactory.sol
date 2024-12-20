// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGearingToken, IOracle} from "../tokens/IGearingToken.sol";
import {IMintableERC20} from "../tokens/MintableERC20.sol";
import {ITermMaxTokenPair} from "../ITermMaxTokenPair.sol";
import "../storage/TermMaxStorage.sol";

/**
 * @title The TermMax factory interface
 * @author Term Structure Labs
 */
interface ITermMaxFactory {
    /// @notice Error for repeat initialization of token pair's implementation
    error TokenPairImplementInitialized();
    /// @notice Error for token pair's implementation were not initialized
    error TokenPairImplementIsNotInitialized();
    /// @notice Error for repeat initialization of market's implementation
    error MarketImplementInitialized();
    /// @notice Error for market's implementation were not initialized
    error MarketImplementIsNotInitialized();
    /// @notice Error for gt implementation can not found
    error CantNotFindGtImplementation();

    /// @notice Emit when initializing implementation of TermMax Token Pair
    event InitializeTokenPairImplement(address marketImplement);
    /// @notice Emit when initializing implementation of TermMax Market
    event InitializeMarketImplement(address marketImplement);
    /// @notice Emit when setting implementations of Gearing Token
    event SetGtImplement(bytes32 key, address gtImplement);

    struct TokenPairDeployParams {
        /// @notice Use gt key to get the implementation of gearing Token
        bytes32 gtKey;
        /// @notice Admin address of market
        address admin;
        /// @notice Collateral token
        address collateral;
        /// @notice Underlying token
        IERC20Metadata underlying;
        /// @notice The oracle aggregator
        IOracle oracle;
        /// @notice The liquidation threshold of loan to collateral in Gearing Token
        uint32 liquidationLtv;
        /// @notice The threshold of loan to collateral when minting Gearing Token
        uint32 maxLtv;
        /// @notice The flag to indicate Gearing Token is liquidatable or not
        bool liquidatable;
        /// @notice Configuturation of new market
        TokenPairConfig tokenPairConfig;
        /// @notice Encoded parameters to initialize GT implementation contract
        bytes gtInitalParams;
    }

    struct MarketDeployParams {
        /// @notice Admin address of market
        address admin;
        /// @notice Contract address of token pair
        ITermMaxTokenPair tokenPair;
        /// @notice Configuturation of new market
        MarketConfig marketConfig;
    }

    /// @notice Set the implementations of TermMax Gearing Token contract
    function setGtImplement(
        string memory gtImplementName,
        address gtImplement
    ) external;

    /// @notice Predict the address of token pair
    function predictTokenPairAddress(
        IERC20Metadata collateral,
        IERC20Metadata underlying,
        uint maturity
    ) external view returns (address tokenPair);

    /// @notice Deploy a new token pair
    function createTokenPair(
        ITermMaxFactory.TokenPairDeployParams calldata deployParams
    ) external returns (address tokenPair);

    /// @notice Predict the address of market
    function predictMarketAddress(
        ITermMaxTokenPair tokenPair,
        address maker
    ) external view returns (address market);

    /// @notice Deploy a new market
    function createMarket(
        ITermMaxFactory.MarketDeployParams calldata deployParams
    ) external returns (address market);
}
