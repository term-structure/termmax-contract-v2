// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TermMax Market Constants V2
 * @author Term Structure Labs
 * @notice Library containing string constants for token naming conventions in TermMax V2 markets
 * @dev Provides standardized prefixes for token names and symbols to ensure consistent naming across the protocol
 * Used during token initialization to create human-readable identifiers for market tokens
 */
library MarketConstantsV2 {
    /// @notice Prefix for Fixed Term token names and symbols (e.g., "FT:USDC-24-Dec")
    /// @dev Fixed Term tokens represent the fixed-rate lending position in a market
    string constant PREFIX_FT = "FT:";
    
    /// @notice Prefix for Variable Term token names and symbols (e.g., "XT:USDC-24-Dec")
    /// @dev Variable Term tokens represent the variable-rate lending position in a market
    string constant PREFIX_XT = "XT:";
    
    /// @notice Prefix for Gearing Token names and symbols (e.g., "GT:USDC-24-Dec")
    /// @dev Gearing Tokens are NFTs representing leveraged positions with collateral backing
    string constant PREFIX_GT = "GT:";
    
    /// @notice Prefix for TermMax Market contract names (e.g., "Termmax Market:USDC-24-Dec")
    /// @dev Used to create human-readable market identifiers for easier recognition and debugging
    /// @dev V2-specific addition for enhanced market identification
    string constant PREFIX_MARKET = "Termmax Market:";
}
