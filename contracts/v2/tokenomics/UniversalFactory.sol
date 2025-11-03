// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title UniversalFactory
 * @notice Universal factory contract for deploying any contract using CREATE2
 * @dev Allows deterministic address prediction before deployment
 *      Salt is computed only from nonce for simplicity
 */
contract UniversalFactory {
    /// @notice Emitted when a new contract is deployed
    event ContractDeployed(
        address indexed deployedAddress,
        address indexed deployer,
        bytes32 indexed salt,
        uint256 nonce
    );

    /// @notice Mapping to track deployed contracts
    mapping(address => bool) public isDeployed;

    /// @notice Mapping to track used nonces to prevent redeployment
    mapping(uint256 => bool) public nonceUsed;

    /**
     * @notice Deploy a new contract using CREATE2
     * @param creationCode The bytecode of the contract to deploy (including constructor arguments)
     * @param nonce A unique value used to generate the deployment salt
     * @return deployedAddress The address of the deployed contract
     */
    function deploy(
        bytes memory creationCode,
        uint256 nonce
    ) external returns (address deployedAddress) {
        require(!nonceUsed[nonce], "UniversalFactory: nonce already used");
        
        // Generate salt from nonce only
        bytes32 salt = bytes32(nonce);

        // Deploy using CREATE2
        assembly {
            deployedAddress := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }

        require(deployedAddress != address(0), "UniversalFactory: deployment failed");

        // Mark nonce as used and track deployment
        nonceUsed[nonce] = true;
        isDeployed[deployedAddress] = true;

        emit ContractDeployed(deployedAddress, msg.sender, salt, nonce);

        return deployedAddress;
    }

    /**
     * @notice Predict the address of a contract before deployment
     * @param creationCode The bytecode of the contract to deploy (including constructor arguments)
     * @param nonce The nonce value to use for salt generation
     * @return predicted The predicted address of the contract
     */
    function predictAddress(
        bytes memory creationCode,
        uint256 nonce
    ) public view returns (address predicted) {
        // Generate the same salt that will be used in deployment
        bytes32 salt = bytes32(nonce);

        // Calculate the hash for CREATE2
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(creationCode)
            )
        );

        // Convert to address (take last 20 bytes)
        predicted = address(uint160(uint256(hash)));

        return predicted;
    }

    /**
     * @notice Get the salt for a given nonce
     * @param nonce The nonce value
     * @return salt The computed salt value
     */
    function getSalt(uint256 nonce) external pure returns (bytes32 salt) {
        return bytes32(nonce);
    }

    /**
     * @notice Helper function to get creation code for a contract with constructor arguments
     * @dev This is a view function to help users compute the creation code off-chain
     * @param contractBytecode The bytecode of the contract
     * @param constructorArgs The ABI-encoded constructor arguments
     * @return creationCode The complete creation code
     */
    function getCreationCode(
        bytes memory contractBytecode,
        bytes memory constructorArgs
    ) external pure returns (bytes memory creationCode) {
        return abi.encodePacked(contractBytecode, constructorArgs);
    }
}
