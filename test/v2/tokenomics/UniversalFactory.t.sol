// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {UniversalFactory} from "../../../contracts/v2/tokenomics/UniversalFactory.sol";
import {TMX} from "../../../contracts/v2/tokenomics/TMX.sol";

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

    function testDeployTMX() public {
        uint256 nonce = 1;

        // Get creation code - TMX now only takes admin parameter
        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));

        // Predict address before deployment
        address predicted = factory.predictAddress(creationCode, nonce);

        // Deploy TMX
        address deployed = factory.deploy(creationCode, nonce);

        // Verify prediction matches actual deployment
        assertEq(predicted, deployed, "Predicted address should match deployed address");

        // Verify TMX contract state
        TMX tmx = TMX(deployed);
        assertEq(tmx.name(), "TermMax", "Token name should be correct");
        assertEq(tmx.symbol(), "TMX", "Token symbol should be correct");
        assertEq(tmx.decimals(), 18, "Token decimals should be 18");
        assertEq(tmx.maxSupply(), MAX_SUPPLY, "Max supply should match");
        assertEq(tmx.totalSupply(), MAX_SUPPLY, "Total supply should equal max supply");
        assertEq(tmx.balanceOf(admin), MAX_SUPPLY, "Admin should have all tokens");

        // Verify factory tracking
        assertTrue(factory.isDeployed(deployed), "Factory should track deployed contract");
        assertTrue(factory.nonceUsed(nonce), "Nonce should be marked as used");
    }

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

    function testDeployWithDifferentNonces() public {
        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));

        address deployed1 = factory.deploy(creationCode, 1);
        address deployed2 = factory.deploy(creationCode, 2);
        address deployed3 = factory.deploy(creationCode, 3);

        // All should be different
        assertTrue(deployed1 != deployed2, "Deployment 1 and 2 should differ");
        assertTrue(deployed2 != deployed3, "Deployment 2 and 3 should differ");
        assertTrue(deployed1 != deployed3, "Deployment 1 and 3 should differ");

        // All should be tracked
        assertTrue(factory.isDeployed(deployed1), "Deployment 1 should be tracked");
        assertTrue(factory.isDeployed(deployed2), "Deployment 2 should be tracked");
        assertTrue(factory.isDeployed(deployed3), "Deployment 3 should be tracked");

        // All nonces should be used
        assertTrue(factory.nonceUsed(1), "Nonce 1 should be used");
        assertTrue(factory.nonceUsed(2), "Nonce 2 should be used");
        assertTrue(factory.nonceUsed(3), "Nonce 3 should be used");
    }

    function testCannotDeployTwiceWithSameNonce() public {
        uint256 nonce = 1;

        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));

        // First deployment should succeed
        factory.deploy(creationCode, nonce);

        // Second deployment with same nonce should fail
        vm.expectRevert("UniversalFactory: nonce already used");
        factory.deploy(creationCode, nonce);
    }

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
    // Address Prediction Tests
    // ============================================

    function testPredictAddressConsistency() public {
        uint256 nonce = 1;

        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));

        // Predict multiple times should give same result
        address predicted1 = factory.predictAddress(creationCode, nonce);
        address predicted2 = factory.predictAddress(creationCode, nonce);
        address predicted3 = factory.predictAddress(creationCode, nonce);

        assertEq(predicted1, predicted2, "First and second predictions should match");
        assertEq(predicted2, predicted3, "Second and third predictions should match");
    }

    function testPredictAddressBeforeAndAfterDeployment() public {
        uint256 nonce = 1;

        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));

        // Predict before deployment
        address predictedBefore = factory.predictAddress(creationCode, nonce);

        // Deploy
        address deployed = factory.deploy(creationCode, nonce);

        // Predict after deployment (should still give same result)
        address predictedAfter = factory.predictAddress(creationCode, nonce);

        assertEq(predictedBefore, deployed, "Prediction before should match deployment");
        assertEq(predictedAfter, deployed, "Prediction after should match deployment");
        assertEq(predictedBefore, predictedAfter, "Predictions should be consistent");
    }

    function testPredictAddressWithDifferentCreationCode() public {
        uint256 nonce = 1;

        // Use different admin addresses to create different creation codes
        bytes memory creationCode1 = abi.encodePacked(type(TMX).creationCode, abi.encode(address(0x1111)));

        bytes memory creationCode2 = abi.encodePacked(type(TMX).creationCode, abi.encode(address(0x2222)));

        address predicted1 = factory.predictAddress(creationCode1, nonce);
        address predicted2 = factory.predictAddress(creationCode2, nonce);

        assertTrue(predicted1 != predicted2, "Different creation codes should produce different addresses");
    }

    function testPredictAddressWithDifferentNonces() public {
        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));

        address predicted1 = factory.predictAddress(creationCode, 1);
        address predicted2 = factory.predictAddress(creationCode, 2);
        address predicted3 = factory.predictAddress(creationCode, 999);

        assertTrue(predicted1 != predicted2, "Nonce 1 and 2 should produce different addresses");
        assertTrue(predicted2 != predicted3, "Nonce 2 and 999 should produce different addresses");
        assertTrue(predicted1 != predicted3, "Nonce 1 and 999 should produce different addresses");
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

    function testGetCreationCode() public {
        bytes memory bytecode = type(TMX).creationCode;
        bytes memory constructorArgs = abi.encode(admin);

        bytes memory creationCode = factory.getCreationCode(bytecode, constructorArgs);
        bytes memory expectedCode = abi.encodePacked(bytecode, constructorArgs);

        assertEq(creationCode, expectedCode, "Creation code should be correctly computed");
    }

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

    function testDeployEmitsEvent() public {
        uint256 nonce = 1;

        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));

        address predicted = factory.predictAddress(creationCode, nonce);
        bytes32 expectedSalt = factory.getSalt(nonce);

        vm.expectEmit(true, true, true, true);
        emit ContractDeployed(predicted, address(this), expectedSalt, nonce);

        factory.deploy(creationCode, nonce);
    }

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

    function testDeployDifferentContractTypes() public {
        // Test deploying multiple TMX contracts with different admin addresses
        uint256 nonce1 = 100;
        uint256 nonce2 = 101;
        uint256 nonce3 = 102;

        bytes memory creationCode1 = abi.encodePacked(type(TMX).creationCode, abi.encode(address(0x1111)));

        bytes memory creationCode2 = abi.encodePacked(type(TMX).creationCode, abi.encode(address(0x2222)));

        bytes memory creationCode3 = abi.encodePacked(type(TMX).creationCode, abi.encode(address(0x3333)));

        address deployed1 = factory.deploy(creationCode1, nonce1);
        address deployed2 = factory.deploy(creationCode2, nonce2);
        address deployed3 = factory.deploy(creationCode3, nonce3);

        // All should be different
        assertTrue(deployed1 != deployed2, "Deployment 1 and 2 should differ");
        assertTrue(deployed2 != deployed3, "Deployment 2 and 3 should differ");
        assertTrue(deployed1 != deployed3, "Deployment 1 and 3 should differ");

        // Verify each contract - all have constant maxSupply of 1e9 ether
        TMX tmx1 = TMX(deployed1);
        TMX tmx2 = TMX(deployed2);
        TMX tmx3 = TMX(deployed3);

        assertEq(tmx1.balanceOf(address(0x1111)), MAX_SUPPLY);
        assertEq(tmx2.balanceOf(address(0x2222)), MAX_SUPPLY);
        assertEq(tmx3.balanceOf(address(0x3333)), MAX_SUPPLY);
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function testFuzzDeployAndPredict(uint256 nonce, address _admin) public {
        // Bound inputs to reasonable values
        vm.assume(_admin != address(0));
        vm.assume(!factory.nonceUsed(nonce));

        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(_admin));

        // Predict address
        address predicted = factory.predictAddress(creationCode, nonce);

        // Deploy
        address deployed = factory.deploy(creationCode, nonce);

        // Verify prediction
        assertEq(predicted, deployed, "Fuzz: Predicted address should match deployed address");

        // Verify contract state - maxSupply is now constant
        TMX tmx = TMX(deployed);
        assertEq(tmx.maxSupply(), MAX_SUPPLY, "Fuzz: Max supply should match");
        assertEq(tmx.balanceOf(_admin), MAX_SUPPLY, "Fuzz: Admin should have all tokens");

        // Verify tracking
        assertTrue(factory.isDeployed(deployed), "Fuzz: Should be marked as deployed");
        assertTrue(factory.nonceUsed(nonce), "Fuzz: Nonce should be marked as used");
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

    function testGasDeployTMXContract() public {
        uint256 gasBefore = gasleft();
        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));
        factory.deploy(creationCode, 1);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for TMX deployment", gasUsed);
        // Just for visibility, no assertion
    }

    function testGasPredictAddress() public {
        bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));

        uint256 gasBefore = gasleft();
        factory.predictAddress(creationCode, 1);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for address prediction", gasUsed);
        // Just for visibility, no assertion
    }

    // ============================================
    // Integration Tests
    // ============================================

    function testSequentialDeployments() public {
        // Deploy 10 TMX contracts sequentially with different admins
        for (uint256 i = 0; i < 10; i++) {
            address currentAdmin = address(uint160(0x1000 + i));
            bytes memory creationCode = abi.encodePacked(type(TMX).creationCode, abi.encode(currentAdmin));

            address predicted = factory.predictAddress(creationCode, i);
            address deployed = factory.deploy(creationCode, i);

            assertEq(predicted, deployed, "Sequential deployment prediction should match");
            assertTrue(factory.isDeployed(deployed), "Sequential deployment should be tracked");
            assertTrue(factory.nonceUsed(i), "Sequential nonce should be used");

            TMX tmx = TMX(deployed);
            assertEq(tmx.maxSupply(), MAX_SUPPLY, "Sequential supply should match constant");
            assertEq(tmx.balanceOf(currentAdmin), MAX_SUPPLY, "Admin should have all tokens");
        }
    }

    function testCrossContractTypeDeployments() public {
        // Deploy different contract types with sequential nonces
        uint256 nonce = 0;

        // Deploy SimpleContract
        bytes memory creationCode1 = type(SimpleContract).creationCode;
        address simple = factory.deploy(creationCode1, nonce++);
        assertTrue(factory.isDeployed(simple), "SimpleContract should be deployed");

        // Deploy TMX
        bytes memory creationCode2 = abi.encodePacked(type(TMX).creationCode, abi.encode(admin));
        address tmx = factory.deploy(creationCode2, nonce++);
        assertTrue(factory.isDeployed(tmx), "TMX should be deployed");

        // Deploy MockContract
        bytes memory creationCode3 = abi.encodePacked(type(MockContract).creationCode, abi.encode(12345, admin, "Test"));
        address mock = factory.deploy(creationCode3, nonce++);
        assertTrue(factory.isDeployed(mock), "MockContract should be deployed");

        // All should have different addresses
        assertTrue(simple != tmx, "Simple and TMX should differ");
        assertTrue(tmx != mock, "TMX and Mock should differ");
        assertTrue(simple != mock, "Simple and Mock should differ");
    }
}
