// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IWhitelistManager
 * @author Term Structure Labs
 * @notice Interface for managing whitelists for different contract modules
 */
interface IWhitelistManager {
    event WhitelistUpdated(address[] contractAddress, ContractModule module, bool approved);

    enum ContractModule {
        ADAPTER,
        ORDER_CALLBACK,
        MARKET,
        ORACLE,
        POOL
    }

    /**
     * @notice Set the whitelist status for contract addresses and module
     * @param contractAddresses Array of addresses to set the whitelist status for
     * @param module The contract module type
     * @param approved Whether the addresses should be approved or not
     */
    function batchSetWhitelist(address[] memory contractAddresses, ContractModule module, bool approved) external;

    /**
     * @notice Check if a contract address is whitelisted for a specific module
     * @param contractAddress The address to check
     * @param module The contract module type
     * @return bool True if the address is whitelisted for the module, false otherwise
     */
    function isWhitelisted(address contractAddress, ContractModule module) external view returns (bool);
}
