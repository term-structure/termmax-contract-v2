// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {GearingTokenWithERC20V2} from "../tokens/GearingTokenWithERC20V2.sol";
import {MarketInitialParams} from "../../v1/storage/TermMaxStorage.sol";
import {FactoryErrors} from "../../v1/errors/FactoryErrors.sol";
import {FactoryEvents} from "../../v1/events/FactoryEvents.sol";
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {ITermMaxFactory} from "../../v1/factory/ITermMaxFactory.sol";
import {FactoryEventsV2} from "../events/FactoryEventsV2.sol";

/**
 * @title TermMax Factory V2
 * @author Term Structure Labs
 * @notice Factory contract for creating TermMax V2 markets with enhanced functionality
 * @dev Manages market deployment, gearing token implementations, and market configuration validation
 * Inherits from V1 factory interface while adding V2-specific features for improved market creation
 */
contract TermMaxFactoryV2 is Ownable2Step, FactoryErrors, FactoryEvents, ITermMaxFactory, FactoryEventsV2 {
    /// @notice Constant key for the default ERC20 gearing token implementation
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

    /// @notice The implementation of TermMax Market contract used as template for cloning
    /// @dev This is set once during construction and cannot be changed
    address public immutable TERMMAX_MARKET_IMPLEMENTATION;

    /// @notice Mapping of gearing token implementation names to their contract addresses
    /// @dev Based on the abstract GearingToken contract, different GearingTokens can be adapted 
    /// to various collaterals, such as ERC20 tokens and ERC721 tokens
    /// @dev Keys are keccak256 hashes of implementation names for gas efficiency
    mapping(bytes32 => address) public gtImplements;

    /**
     * @notice Constructs the TermMax Factory V2 with initial configurations
     * @dev Sets up the factory with a market implementation and deploys the default ERC20 gearing token
     * @param admin The address that will have administrative privileges over the factory
     * @param TERMMAX_MARKET_IMPLEMENTATION_ The address of the TermMax market implementation contract
     * @custom:security Only the admin can create markets and manage gearing token implementations
     */
    constructor(address admin, address TERMMAX_MARKET_IMPLEMENTATION_) Ownable(admin) {
        if (TERMMAX_MARKET_IMPLEMENTATION_ == address(0)) {
            revert InvalidImplementation();
        }
        TERMMAX_MARKET_IMPLEMENTATION = TERMMAX_MARKET_IMPLEMENTATION_;

        // Deploy and register the default ERC20 gearing token implementation
        gtImplements[GT_ERC20] = address(new GearingTokenWithERC20V2());
    }

    /**
     * @notice Registers a new gearing token implementation with a given name
     * @dev Allows the factory to support different types of gearing tokens for various collateral types
     * @param gtImplementName The string name of the gearing token implementation
     * @param gtImplement The contract address of the gearing token implementation
     * @custom:access Only the factory owner can register new implementations
     * @custom:events Emits SetGtImplement event for tracking implementation changes
     */
    function setGtImplement(string memory gtImplementName, address gtImplement) external onlyOwner {
        bytes32 key = keccak256(abi.encodePacked(gtImplementName));
        gtImplements[key] = gtImplement;
        emit SetGtImplement(key, gtImplement);
    }

    /**
     * @notice Predicts the address where a market will be deployed before actual creation
     * @dev Uses CREATE2 deterministic deployment to calculate the future market address
     * @param deployer The address that will deploy the market (msg.sender during createMarket)
     * @param collateral The address of the collateral token for the market
     * @param debtToken The address of the debt token for the market
     * @param maturity The maturity timestamp of the market
     * @param salt Additional salt value for address generation uniqueness
     * @return market The predicted address where the market will be deployed
     * @custom:view This is a view function that doesn't modify state
     */
    function predictMarketAddress(
        address deployer,
        address collateral,
        address debtToken,
        uint64 maturity,
        uint256 salt
    ) external view returns (address market) {
        return Clones.predictDeterministicAddress(
            TERMMAX_MARKET_IMPLEMENTATION, keccak256(abi.encode(deployer, collateral, debtToken, maturity, salt))
        );
    }

    /**
     * @notice Creates a new TermMax market with specified parameters
     * @dev Clones the market implementation and initializes it with the provided parameters
     * @param gtKey The key identifying which gearing token implementation to use
     * @param params The initial parameters for market configuration including collateral, debt token, and settings
     * @param salt Additional entropy for deterministic address generation
     * @return market The address of the newly created market contract
     * @custom:access Only the factory owner can create new markets
     * @custom:validation Validates that the requested gearing token implementation exists
     * @custom:events Emits CreateMarket event with market details for indexing and monitoring
     */
    function createMarket(bytes32 gtKey, MarketInitialParams memory params, uint256 salt)
        external
        onlyOwner
        returns (address market)
    {
        // Retrieve the gearing token implementation for the requested key
        params.gtImplementation = gtImplements[gtKey];
        if (params.gtImplementation == address(0)) {
            revert CantNotFindGtImplementation();
        }
        
        // Deploy market using CREATE2 for deterministic addressing
        market = Clones.cloneDeterministic(
            TERMMAX_MARKET_IMPLEMENTATION,
            keccak256(abi.encode(msg.sender, params.collateral, params.debtToken, params.marketConfig.maturity, salt))
        );
        
        // Initialize the newly deployed market with provided parameters
        ITermMaxMarket(market).initialize(params);

        // Emit event for market creation tracking
        emit CreateMarket(market, params.collateral, params.debtToken, params);
    }
}
