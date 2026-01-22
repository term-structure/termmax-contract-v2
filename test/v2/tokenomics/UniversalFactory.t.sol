// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {UniversalFactory} from "../../../contracts/v2/tokenomics/UniversalFactory.sol";

// Mock contract for testing various deployment scenarios
contract MockContract {
    uint256 public value;
    address public owner;
    string public name;

    constructor(uint256 _value, address _owner, string memory _name) {
        value = _value;
        owner = _owner;
        name = _name;
    }

    function getValue() external view returns (uint256) {
        return value;
    }
}

// Simple contract with no constructor arguments
contract SimpleContract {
    uint256 public constant FIXED_VALUE = 42;

    function getFixedValue() external pure returns (uint256) {
        return FIXED_VALUE;
    }
}

// Contract with payable constructor
contract PayableContract {
    uint256 public receivedValue;

    constructor() payable {
        receivedValue = msg.value;
    }
}

contract UniversalFactoryTest is Test {
    UniversalFactory public factory;
    address public admin = address(0x1234);
    address public user1 = address(0x5678);
    address public user2 = address(0x9ABC);
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    event ContractDeployed(
        address indexed deployedAddress, address indexed deployer, bytes32 indexed salt, uint256 nonce
    );

    function setUp() public {
        factory = new UniversalFactory();
    }

    // ============================================
    // Basic Deployment Tests
    // ============================================

    function testDeploySimpleContract() public {
        uint256 nonce = 1;

        bytes memory creationCode = type(SimpleContract).creationCode;

        address predicted = factory.predictAddress(creationCode, nonce);
        address deployed = factory.deploy(creationCode, nonce);

        assertEq(predicted, deployed, "Predicted address should match deployed address");

        SimpleContract simple = SimpleContract(deployed);
        assertEq(simple.getFixedValue(), 42, "Fixed value should be 42");
        assertEq(simple.FIXED_VALUE(), 42, "Constant should be 42");
    }

    function testDeployMockContract() public {
        uint256 nonce = 1;
        uint256 value = 12345;
        address owner = address(0xABCD);
        string memory name = "TestMock";

        bytes memory creationCode = abi.encodePacked(type(MockContract).creationCode, abi.encode(value, owner, name));

        address predicted = factory.predictAddress(creationCode, nonce);
        address deployed = factory.deploy(creationCode, nonce);

        assertEq(predicted, deployed, "Predicted address should match deployed address");

        MockContract mock = MockContract(deployed);
        assertEq(mock.value(), value, "Value should match");
        assertEq(mock.owner(), owner, "Owner should match");
        assertEq(mock.name(), name, "Name should match");
        assertEq(mock.getValue(), value, "getValue should return correct value");
    }

    // ============================================
    // Nonce Management Tests
    // ============================================

    function testNonceUsedInitiallyFalse() public {
        assertFalse(factory.nonceUsed(1), "Nonce 1 should not be used initially");
        assertFalse(factory.nonceUsed(999), "Nonce 999 should not be used initially");
        assertFalse(factory.nonceUsed(type(uint256).max), "Max nonce should not be used initially");
    }

    function testNonceUsedAfterDeployment() public {
        uint256 nonce = 42;
        assertFalse(factory.nonceUsed(nonce), "Nonce should not be used before deployment");

        bytes memory creationCode = type(SimpleContract).creationCode;
        factory.deploy(creationCode, nonce);

        assertTrue(factory.nonceUsed(nonce), "Nonce should be used after deployment");
    }

    // ============================================
    // Salt Generation Tests
    // ============================================

    function testGetSalt() public {
        assertEq(factory.getSalt(0), bytes32(uint256(0)), "Salt for nonce 0 should be 0");
        assertEq(factory.getSalt(1), bytes32(uint256(1)), "Salt for nonce 1 should be 1");
        assertEq(factory.getSalt(123), bytes32(uint256(123)), "Salt for nonce 123 should be 123");
        assertEq(factory.getSalt(type(uint256).max), bytes32(type(uint256).max), "Salt for max nonce should be max");
    }

    function testSaltIsDirectNonceConversion() public {
        uint256 nonce = 42;
        bytes32 salt = factory.getSalt(nonce);
        bytes32 expectedSalt = bytes32(nonce);

        assertEq(salt, expectedSalt, "Salt should be direct conversion of nonce");
    }

    // ============================================
    // Creation Code Helper Tests
    // ============================================

    function testGetCreationCodeWithEmptyArgs() public {
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory constructorArgs = "";

        bytes memory creationCode = factory.getCreationCode(bytecode, constructorArgs);

        assertEq(creationCode, bytecode, "Creation code without args should equal bytecode");
    }

    function testGetCreationCodeWithComplexArgs() public {
        bytes memory bytecode = type(MockContract).creationCode;
        uint256 value = 12345;
        address owner = address(0xABCD);
        string memory name = "TestContract";
        bytes memory constructorArgs = abi.encode(value, owner, name);

        bytes memory creationCode = factory.getCreationCode(bytecode, constructorArgs);
        bytes memory expectedCode = abi.encodePacked(bytecode, constructorArgs);

        assertEq(creationCode, expectedCode, "Creation code with complex args should be correct");
    }

    // ============================================
    // Event Emission Tests
    // ============================================

    function testMultipleDeploymentsEmitMultipleEvents() public {
        bytes memory creationCode = type(SimpleContract).creationCode;

        for (uint256 i = 1; i <= 3; i++) {
            address predicted = factory.predictAddress(creationCode, i);
            bytes32 expectedSalt = factory.getSalt(i);

            vm.expectEmit(true, true, true, true);
            emit ContractDeployed(predicted, address(this), expectedSalt, i);

            factory.deploy(creationCode, i);
        }
    }

    // ============================================
    // Multi-Deployer Tests
    // ============================================

    function testMultipleDeployersCanUseSameNonce() public {
        uint256 nonce = 1;
        bytes memory creationCode = type(SimpleContract).creationCode;

        // First deployer (this test contract)
        address deployed1 = factory.deploy(creationCode, nonce);

        // Nonce should be used now
        assertTrue(factory.nonceUsed(nonce), "Nonce should be used after first deployment");

        // Second deployer cannot use the same nonce
        vm.prank(user1);
        vm.expectRevert("UniversalFactory: nonce already used");
        factory.deploy(creationCode, nonce);

        // But second deployer can use different nonce
        vm.prank(user1);
        address deployed2 = factory.deploy(creationCode, 2);

        assertTrue(deployed1 != deployed2, "Different deployments should have different addresses");
    }

    function testDeployerAddressInEvent() public {
        uint256 nonce = 1;
        bytes memory creationCode = type(SimpleContract).creationCode;

        address predicted = factory.predictAddress(creationCode, nonce);

        // Deploy from user1
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ContractDeployed(predicted, user1, bytes32(nonce), nonce);
        factory.deploy(creationCode, nonce);
    }

    // ============================================
    // Edge Cases Tests
    // ============================================

    function testDeployWithNonceZero() public {
        uint256 nonce = 0;
        bytes memory creationCode = type(SimpleContract).creationCode;

        address predicted = factory.predictAddress(creationCode, nonce);
        address deployed = factory.deploy(creationCode, nonce);

        assertEq(predicted, deployed, "Nonce 0 should work correctly");
        assertTrue(factory.nonceUsed(0), "Nonce 0 should be marked as used");
    }

    function testDeployWithMaxNonce() public {
        uint256 nonce = type(uint256).max;
        bytes memory creationCode = type(SimpleContract).creationCode;

        address predicted = factory.predictAddress(creationCode, nonce);
        address deployed = factory.deploy(creationCode, nonce);

        assertEq(predicted, deployed, "Max nonce should work correctly");
        assertTrue(factory.nonceUsed(type(uint256).max), "Max nonce should be marked as used");
    }

    function testIsDeployedInitiallyFalse() public {
        address randomAddress = address(0x1234567890);
        assertFalse(factory.isDeployed(randomAddress), "Random address should not be marked as deployed");
    }

    function testIsDeployedAfterDeployment() public {
        uint256 nonce = 1;
        bytes memory creationCode = type(SimpleContract).creationCode;

        address deployed = factory.deploy(creationCode, nonce);

        assertTrue(factory.isDeployed(deployed), "Deployed address should be marked as deployed");
    }

    function testFuzzGetSalt(uint256 nonce) public {
        bytes32 salt = factory.getSalt(nonce);
        assertEq(salt, bytes32(nonce), "Fuzz: Salt should equal nonce");
    }

    function testFuzzPredictAddressConsistency(uint256 nonce) public {
        bytes memory creationCode = type(SimpleContract).creationCode;

        address predicted1 = factory.predictAddress(creationCode, nonce);
        address predicted2 = factory.predictAddress(creationCode, nonce);

        assertEq(predicted1, predicted2, "Fuzz: Predictions should be consistent");
    }

    function testFuzzMultipleNoncesDifferentAddresses(uint256 nonce1, uint256 nonce2) public {
        vm.assume(nonce1 != nonce2);
        vm.assume(!factory.nonceUsed(nonce1));
        vm.assume(!factory.nonceUsed(nonce2));

        bytes memory creationCode = type(SimpleContract).creationCode;

        address predicted1 = factory.predictAddress(creationCode, nonce1);
        address predicted2 = factory.predictAddress(creationCode, nonce2);

        assertTrue(predicted1 != predicted2, "Fuzz: Different nonces should produce different addresses");

        address deployed1 = factory.deploy(creationCode, nonce1);
        address deployed2 = factory.deploy(creationCode, nonce2);

        assertTrue(deployed1 != deployed2, "Fuzz: Deployed addresses should differ");
        assertEq(predicted1, deployed1, "Fuzz: First prediction should match");
        assertEq(predicted2, deployed2, "Fuzz: Second prediction should match");
    }

    // ============================================
    // Gas Benchmarking Tests
    // ============================================

    function testGasDeploySimpleContract() public {
        uint256 gasBefore = gasleft();
        bytes memory creationCode = type(SimpleContract).creationCode;
        factory.deploy(creationCode, 1);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for simple contract deployment", gasUsed);
        // Just for visibility, no assertion
    }

    // ============================================
    // Integration Tests
    // ============================================

    function testCrossContractTypeDeployments() public {
        // Deploy different contract types with sequential nonces
        uint256 nonce = 0;

        // Deploy SimpleContract
        bytes memory creationCode1 = type(SimpleContract).creationCode;
        address simple = factory.deploy(creationCode1, nonce++);
        assertTrue(factory.isDeployed(simple), "SimpleContract should be deployed");

        // Deploy MockContract
        bytes memory creationCode3 = abi.encodePacked(type(MockContract).creationCode, abi.encode(12345, admin, "Test"));
        address mock = factory.deploy(creationCode3, nonce++);
        assertTrue(factory.isDeployed(mock), "MockContract should be deployed");

        assertTrue(simple != mock, "Simple and Mock should differ");
    }
}
