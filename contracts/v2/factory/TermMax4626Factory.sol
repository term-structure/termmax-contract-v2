// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {StakingBuffer} from "../tokens/StakingBuffer.sol";
import {StableERC4626For4626} from "../tokens/StableERC4626For4626.sol";
import {StableERC4626ForAave} from "../tokens/StableERC4626ForAave.sol";
import {VariableERC4626ForAave} from "../tokens/VariableERC4626ForAave.sol";
import {FactoryEventsV2} from "../events/FactoryEventsV2.sol";
import {VersionV2} from "../VersionV2.sol";

contract TermMax4626Factory is VersionV2 {
    using Clones for address;

    address public immutable stableERC4626For4626Implementation;
    address public immutable stableERC4626ForAaveImplementation;
    address public immutable variableERC4626ForAaveImplementation;

    constructor(address aavePool, uint16 aaveReferralCode) {
        stableERC4626For4626Implementation = address(new StableERC4626For4626());
        stableERC4626ForAaveImplementation = address(new StableERC4626ForAave(aavePool, aaveReferralCode));
        variableERC4626ForAaveImplementation = address(new VariableERC4626ForAave(aavePool, aaveReferralCode));
        emit FactoryEventsV2.TermMax4626FactoryInitialized(
            aavePool,
            aaveReferralCode,
            stableERC4626For4626Implementation,
            stableERC4626ForAaveImplementation,
            variableERC4626ForAaveImplementation
        );
    }

    function createStableERC4626For4626(
        address admin,
        address thirdPool,
        StakingBuffer.BufferConfig memory bufferConfig
    ) external returns (StableERC4626For4626) {
        StableERC4626For4626 instance = StableERC4626For4626(stableERC4626For4626Implementation.clone());
        instance.initialize(admin, thirdPool, bufferConfig);
        emit FactoryEventsV2.StableERC4626For4626Created(msg.sender, address(instance));
        return instance;
    }

    function createStableERC4626ForAave(
        address admin,
        address underlying,
        StakingBuffer.BufferConfig memory bufferConfig
    ) public returns (StableERC4626ForAave) {
        StableERC4626ForAave instance = StableERC4626ForAave(stableERC4626ForAaveImplementation.clone());
        instance.initialize(admin, underlying, bufferConfig);
        emit FactoryEventsV2.StableERC4626ForAaveCreated(msg.sender, address(instance));
        return instance;
    }

    function createVariableERC4626ForAave(
        address admin,
        address underlying,
        StakingBuffer.BufferConfig memory bufferConfig
    ) public returns (VariableERC4626ForAave) {
        VariableERC4626ForAave instance = VariableERC4626ForAave(variableERC4626ForAaveImplementation.clone());
        instance.initialize(admin, underlying, bufferConfig);
        emit FactoryEventsV2.VariableERC4626ForAaveCreated(msg.sender, address(instance));
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
