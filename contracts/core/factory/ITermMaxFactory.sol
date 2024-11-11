// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGearingToken, AggregatorV3Interface} from "../tokens/IGearingToken.sol";
import {IMintableERC20} from "../tokens/MintableERC20.sol";
import "../storage/TermMaxStorage.sol";

/**
 * @title The Term Max factory interface
 * @author Term Structure Labs
 */
interface ITermMaxFactory {
    /// @notice Error for repeat initialization of market's implementation
    error MarketImplementInitialized();
    /// @notice Error for market's implementation were not initialized
    error MarketImplementIsNotInitialized();
    /// @notice Error for gt implementation can not found
    error CantNotFindGtImplementation();

    /// @notice Emit when initializing implementation of Term Max Market
    event InitializeMarketImplement(address marketImplement);
    /// @notice Emit when setting implementations of Gearing Token
    event SetGtImplement(bytes32 key, address gtImplement);

    struct DeployParams {
        /// @notice Use gt key to get the implementation of gearing Token
        bytes32 gtKey;
        /// @notice Admin address of market
        address admin;
        /// @notice Collateral token
        address collateral;
        /// @notice Underlying token
        IERC20Metadata underlying;
        /// @notice The oracle of underlying token
        AggregatorV3Interface underlyingOracle;
        /// @notice The liquidation threshold of loan to collateral in Gearing Token
        uint32 liquidationLtv;
        /// @notice The threshold of loan to collateral when minting Gearing Token
        uint32 maxLtv;
        /// @notice The flag to indicate Gearing Token is liquidatable or not
        bool liquidatable;
        /// @notice Configuturation of new market
        MarketConfig marketConfig;
        /// @notice Encoded parameters to initialize GT implementation contract
        bytes gtInitalParams;
    }

    /// @notice Deploy a new market
    function createMarket(
        ITermMaxFactory.DeployParams calldata deployParams
    ) external returns (address market);

    /// @notice Predict the address of market
    function predictMarketAddress(
        address collateral,
        IERC20Metadata underlying,
        uint64 openTime,
        uint64 maturity,
        uint32 initialLtv
    ) external view returns (address market);
}
