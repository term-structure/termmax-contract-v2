// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {StakingBuffer} from "../tokens/StakingBuffer.sol";
import {StableERC4626For4626} from "../tokens/StableERC4626For4626.sol";
import {StableERC4626ForAave} from "../tokens/StableERC4626ForAave.sol";
import {StableERC4626ForVenus} from "../tokens/StableERC4626ForVenus.sol";
import {StableERC4626ForCustomize} from "../tokens/StableERC4626ForCustomize.sol";
import {VariableERC4626ForAave} from "../tokens/VariableERC4626ForAave.sol";
import {FactoryEventsV2} from "../events/FactoryEventsV2.sol";
import {FactoryErrorsV2} from "../errors/FactoryErrorsV2.sol";
import {VersionV2} from "../VersionV2.sol";

contract TermMax4626Factory is VersionV2, Ownable2Step {
    using Clones for address;

    bytes32 public constant STABLE_ERC4626_FOR_4626 = keccak256("StableERC4626For4626");
    bytes32 public constant STABLE_ERC4626_FOR_AAVE = keccak256("StableERC4626ForAave");
    bytes32 public constant STABLE_ERC4626_FOR_VENUS = keccak256("StableERC4626ForVenus");
    bytes32 public constant VARIABLE_ERC4626_FOR_AAVE = keccak256("VariableERC4626ForAave");
    bytes32 public constant STABLE_ERC4626_FOR_CUSTOMIZE = keccak256("StableERC4626ForCustomize");

    mapping(bytes32 => address) internal implementations;

    constructor(
        address owner,
        address _stableERC4626For4626Implementation,
        address _stableERC4626ForAaveImplementation,
        address _stableERC4626ForVenusImplementation,
        address _variableERC4626ForAaveImplementation,
        address _stableERC4626ForCustomizeImplementation
    ) Ownable(owner) {
        implementations[STABLE_ERC4626_FOR_4626] = _stableERC4626For4626Implementation;
        implementations[STABLE_ERC4626_FOR_AAVE] = _stableERC4626ForAaveImplementation;
        implementations[STABLE_ERC4626_FOR_VENUS] = _stableERC4626ForVenusImplementation;
        implementations[VARIABLE_ERC4626_FOR_AAVE] = _variableERC4626ForAaveImplementation;
        implementations[STABLE_ERC4626_FOR_CUSTOMIZE] = _stableERC4626ForCustomizeImplementation;

        emit FactoryEventsV2.TermMax4626FactoryInitialized(
            _stableERC4626For4626Implementation,
            _stableERC4626ForAaveImplementation,
            _variableERC4626ForAaveImplementation,
            _stableERC4626ForVenusImplementation,
            _stableERC4626ForCustomizeImplementation
        );
    }

    function getImplementations(string memory key) external view returns (address) {
        return implementations[keccak256(abi.encodePacked(key))];
    }

    function setImplementation(string memory key, address implementation) external onlyOwner {
        implementations[keccak256(abi.encodePacked(key))] = implementation;
        emit FactoryEventsV2.ImplementationSet(key, implementation);
    }

    function stableERC4626For4626Implementation() external view returns (address) {
        return implementations[STABLE_ERC4626_FOR_4626];
    }

    function stableERC4626ForAaveImplementation() external view returns (address) {
        return implementations[STABLE_ERC4626_FOR_AAVE];
    }

    function stableERC4626ForVenusImplementation() external view returns (address) {
        return implementations[STABLE_ERC4626_FOR_VENUS];
    }

    function variableERC4626ForAaveImplementation() external view returns (address) {
        return implementations[VARIABLE_ERC4626_FOR_AAVE];
    }

    function stableERC4626ForCustomizeImplementation() external view returns (address) {
        return implementations[STABLE_ERC4626_FOR_CUSTOMIZE];
    }

    function createStableERC4626For4626(
        address admin,
        address thirdPool,
        StakingBuffer.BufferConfig memory bufferConfig
    ) external returns (StableERC4626For4626) {
        StableERC4626For4626 instance = StableERC4626For4626(implementations[STABLE_ERC4626_FOR_4626].clone());
        instance.initialize(admin, thirdPool, bufferConfig);
        emit FactoryEventsV2.StableERC4626For4626Created(msg.sender, address(instance));
        return instance;
    }

    function createStableERC4626ForVenus(
        address admin,
        address thirdPool,
        StakingBuffer.BufferConfig memory bufferConfig
    ) external returns (StableERC4626ForVenus) {
        StableERC4626ForVenus instance = StableERC4626ForVenus(implementations[STABLE_ERC4626_FOR_VENUS].clone());
        instance.initialize(admin, thirdPool, bufferConfig);
        emit FactoryEventsV2.StableERC4626ForVenusCreated(msg.sender, address(instance));
        return instance;
    }

    function createStableERC4626ForCustomize(
        address admin,
        address thirdPool,
        address underlying,
        StakingBuffer.BufferConfig memory bufferConfig
    ) external returns (StableERC4626ForCustomize) {
        StableERC4626ForCustomize instance =
            StableERC4626ForCustomize(implementations[STABLE_ERC4626_FOR_CUSTOMIZE].clone());
        instance.initialize(admin, thirdPool, underlying, bufferConfig);
        emit FactoryEventsV2.StableERC4626ForCustomizeCreated(msg.sender, address(instance));
        return instance;
    }

    function createStableERC4626ForAave(
        address admin,
        address underlying,
        StakingBuffer.BufferConfig memory bufferConfig
    ) public returns (StableERC4626ForAave) {
        StableERC4626ForAave instance = StableERC4626ForAave(implementations[STABLE_ERC4626_FOR_AAVE].clone());
        instance.initialize(admin, underlying, bufferConfig);
        emit FactoryEventsV2.StableERC4626ForAaveCreated(msg.sender, address(instance));
        return instance;
    }

    function createVariableERC4626ForAave(
        address admin,
        address underlying,
        StakingBuffer.BufferConfig memory bufferConfig
    ) public returns (VariableERC4626ForAave) {
        VariableERC4626ForAave instance = VariableERC4626ForAave(implementations[VARIABLE_ERC4626_FOR_AAVE].clone());
        instance.initialize(admin, underlying, bufferConfig);
        emit FactoryEventsV2.VariableERC4626ForAaveCreated(msg.sender, address(instance));
        return instance;
    }

    function create(string memory key, bytes memory initialData) external returns (address) {
        address implementation = implementations[keccak256(abi.encodePacked(key))];
        if (implementation == address(0)) revert FactoryErrorsV2.ImplementationNotFound(key);
        address instance = implementation.clone();
        (bool success,) = instance.call(initialData);
        if (!success) revert FactoryErrorsV2.InitializationFailed();
        emit FactoryEventsV2.TermMax4626Created(msg.sender, key, instance);
        return instance;
    }

    function createVariableAndStableERC4626ForAave(
        address admin,
        address underlying,
        StakingBuffer.BufferConfig memory bufferConfig
    ) external returns (VariableERC4626ForAave, StableERC4626ForAave) {
        VariableERC4626ForAave variableInstance = createVariableERC4626ForAave(admin, underlying, bufferConfig);
        StableERC4626ForAave stableInstance = createStableERC4626ForAave(admin, underlying, bufferConfig);
        return (variableInstance, stableInstance);
    }
}
