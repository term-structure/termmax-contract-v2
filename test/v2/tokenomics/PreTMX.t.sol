// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {PreTMX, WhitelistConfig} from "../../../contracts/v2/tokenomics/PreTMX.sol";

contract PreTMXTest is Test {
    PreTMX public preTMX;

    address public admin;
    address public user1;
    address public user2;
    address public user3;

    uint256 constant INITIAL_SUPPLY = 1e9 ether;
    uint256 constant TRANSFER_AMOUNT = 100 ether;

    event TransferEnabled(bool enabled);
    event TransferWhitelisted(address wallet, bool isFromWhitelisted, bool isToWhitelisted);

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.prank(admin);
        preTMX = new PreTMX(admin);
    }

    // ========== Deployment & Initial State Tests ==========

    function test_InitialState() public view {
        assertEq(preTMX.totalSupply(), INITIAL_SUPPLY, "Initial supply should be 1B");
        assertEq(preTMX.balanceOf(admin), INITIAL_SUPPLY, "Admin should have all initial tokens");
        assertEq(preTMX.transferEnabled(), false, "Transfer should be disabled by default");
        assertEq(preTMX.owner(), admin, "Owner should be admin");
        assertEq(preTMX.name(), "Pre TermMax Token", "Token name should be correct");
        assertEq(preTMX.symbol(), "pTMX", "Token symbol should be correct");
    }

    function test_AdminWhitelistedOnDeployment() public view {
        (bool fromWhitelisted, bool toWhitelisted) = preTMX.whitelistConfig(admin);
        assertTrue(fromWhitelisted, "Admin should be fromWhitelisted");
        assertTrue(toWhitelisted, "Admin should be toWhitelisted");
    }

    // ========== Transfer Enabled = true Tests ==========

    function test_TransferEnabled_NonWhitelistedToNonWhitelisted() public {
        // Setup: Give user1 some tokens and enable transfer
        vm.prank(admin);
        preTMX.transfer(user1, TRANSFER_AMOUNT);

        vm.prank(admin);
        preTMX.enableTransfer();

        // Execute
        vm.prank(user1);
        preTMX.transfer(user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
        assertEq(preTMX.balanceOf(user1), 0);
    }

    function test_TransferEnabled_FromWhitelistedToNonWhitelisted() public {
        // Setup
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user1, true, false);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        preTMX.enableTransfer();
        vm.stopPrank();

        // Execute
        vm.prank(user1);
        preTMX.transfer(user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    function test_TransferEnabled_NonWhitelistedToToWhitelisted() public {
        // Setup
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user2, false, true);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        preTMX.enableTransfer();
        vm.stopPrank();

        // Execute
        vm.prank(user1);
        preTMX.transfer(user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    function test_TransferEnabled_BothWhitelisted() public {
        // Setup
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user1, true, true);
        preTMX.whitelistTransfer(user2, true, true);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        preTMX.enableTransfer();
        vm.stopPrank();

        // Execute
        vm.prank(user1);
        preTMX.transfer(user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    // ========== Transfer Disabled = false Tests ==========

    function test_TransferDisabled_NonWhitelistedToNonWhitelisted_Reverts() public {
        // Setup: Give user1 some tokens (admin can transfer when disabled)
        vm.prank(admin);
        preTMX.transfer(user1, TRANSFER_AMOUNT);

        // Execute & Assert
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferNotWhitelisted.selector, user1, user2));
        preTMX.transfer(user2, TRANSFER_AMOUNT);
    }

    function test_TransferDisabled_FromWhitelistedToNonWhitelisted_Succeeds() public {
        // Setup
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user1, true, false);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        vm.stopPrank();

        // Execute
        vm.prank(user1);
        preTMX.transfer(user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
        assertEq(preTMX.balanceOf(user1), 0);
    }

    function test_TransferDisabled_NonWhitelistedToToWhitelisted_Succeeds() public {
        // Setup
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user2, false, true);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        vm.stopPrank();

        // Execute
        vm.prank(user1);
        preTMX.transfer(user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    function test_TransferDisabled_FromWhitelistedToToWhitelisted_Succeeds() public {
        // Setup
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user1, true, false);
        preTMX.whitelistTransfer(user2, false, true);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        vm.stopPrank();

        // Execute
        vm.prank(user1);
        preTMX.transfer(user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    function test_TransferDisabled_BothWhitelistedToNonWhitelisted_Succeeds() public {
        // Setup: user1 is whitelisted for both from and to
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user1, true, true);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        vm.stopPrank();

        // Execute: user1 (fromWhitelisted) can send to non-whitelisted user2
        vm.prank(user1);
        preTMX.transfer(user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    function test_TransferDisabled_NonWhitelistedToBothWhitelisted_Succeeds() public {
        // Setup: user2 is whitelisted for both from and to
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user2, true, true);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        vm.stopPrank();

        // Execute: non-whitelisted user1 can send to user2 (toWhitelisted)
        vm.prank(user1);
        preTMX.transfer(user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    // ========== TransferFrom Tests ==========

    function test_TransferFrom_WithApproval_FollowsWhitelistRules() public {
        // Setup: user1 has tokens and approves user3 to spend
        vm.prank(admin);
        preTMX.transfer(user1, TRANSFER_AMOUNT);

        vm.prank(user1);
        preTMX.approve(user3, TRANSFER_AMOUNT);

        // Execute & Assert: Should revert since user1 is not fromWhitelisted
        vm.prank(user3);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferNotWhitelisted.selector, user1, user2));
        preTMX.transferFrom(user1, user2, TRANSFER_AMOUNT);
    }

    function test_TransferFrom_FromWhitelisted_Succeeds() public {
        // Setup
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user1, true, false);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        vm.stopPrank();

        vm.prank(user1);
        preTMX.approve(user3, TRANSFER_AMOUNT);

        // Execute: user3 can transferFrom user1 (fromWhitelisted) to user2
        vm.prank(user3);
        preTMX.transferFrom(user1, user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    function test_TransferFrom_ToWhitelisted_Succeeds() public {
        // Setup
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user2, false, true);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        vm.stopPrank();

        vm.prank(user1);
        preTMX.approve(user3, TRANSFER_AMOUNT);

        // Execute: user3 can transferFrom user1 to user2 (toWhitelisted)
        vm.prank(user3);
        preTMX.transferFrom(user1, user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    function test_TransferFrom_WhenEnabled_Succeeds() public {
        // Setup
        vm.startPrank(admin);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        preTMX.enableTransfer();
        vm.stopPrank();

        vm.prank(user1);
        preTMX.approve(user3, TRANSFER_AMOUNT);

        // Execute
        vm.prank(user3);
        preTMX.transferFrom(user1, user2, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user2), TRANSFER_AMOUNT);
    }

    // ========== Owner Functions Tests ==========

    function test_EnableTransfer_OnlyOwner() public {
        vm.prank(admin);
        preTMX.enableTransfer();

        assertTrue(preTMX.transferEnabled());
    }

    function test_EnableTransfer_NonOwner_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        preTMX.enableTransfer();
    }

    function test_DisableTransfer_OnlyOwner() public {
        vm.startPrank(admin);
        preTMX.enableTransfer();
        preTMX.disableTransfer();
        vm.stopPrank();

        assertFalse(preTMX.transferEnabled());
    }

    function test_DisableTransfer_NonOwner_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        preTMX.disableTransfer();
    }

    function test_WhitelistTransfer_OnlyOwner() public {
        vm.prank(admin);
        preTMX.whitelistTransfer(user1, true, false);

        (bool fromWhitelisted, bool toWhitelisted) = preTMX.whitelistConfig(user1);
        assertTrue(fromWhitelisted);
        assertFalse(toWhitelisted);
    }

    function test_WhitelistTransfer_NonOwner_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        preTMX.whitelistTransfer(user2, true, false);
    }

    function test_Mint_OnlyOwner() public {
        uint256 initialSupply = preTMX.totalSupply();

        vm.prank(admin);
        preTMX.mint(user1, TRANSFER_AMOUNT);

        assertEq(preTMX.balanceOf(user1), TRANSFER_AMOUNT);
        assertEq(preTMX.totalSupply(), initialSupply + TRANSFER_AMOUNT);
    }

    function test_Mint_NonOwner_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        preTMX.mint(user1, TRANSFER_AMOUNT);
    }

    function test_Burn_OnlyOwner() public {
        uint256 initialSupply = preTMX.totalSupply();

        vm.prank(admin);
        preTMX.burn(TRANSFER_AMOUNT);

        assertEq(preTMX.balanceOf(admin), initialSupply - TRANSFER_AMOUNT);
        assertEq(preTMX.totalSupply(), initialSupply - TRANSFER_AMOUNT);
    }

    function test_Burn_NonOwner_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        preTMX.burn(TRANSFER_AMOUNT);
    }

    // ========== Whitelist Management Tests ==========

    function test_WhitelistFromOnly() public {
        vm.prank(admin);
        preTMX.whitelistTransfer(user1, true, false);

        (bool fromWhitelisted, bool toWhitelisted) = preTMX.whitelistConfig(user1);
        assertTrue(fromWhitelisted);
        assertFalse(toWhitelisted);
    }

    function test_WhitelistToOnly() public {
        vm.prank(admin);
        preTMX.whitelistTransfer(user1, false, true);

        (bool fromWhitelisted, bool toWhitelisted) = preTMX.whitelistConfig(user1);
        assertFalse(fromWhitelisted);
        assertTrue(toWhitelisted);
    }

    function test_WhitelistBoth() public {
        vm.prank(admin);
        preTMX.whitelistTransfer(user1, true, true);

        (bool fromWhitelisted, bool toWhitelisted) = preTMX.whitelistConfig(user1);
        assertTrue(fromWhitelisted);
        assertTrue(toWhitelisted);
    }

    function test_RemoveWhitelist() public {
        // Setup: whitelist user1
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user1, true, true);

        // Execute: remove whitelist
        preTMX.whitelistTransfer(user1, false, false);
        vm.stopPrank();

        // Assert
        (bool fromWhitelisted, bool toWhitelisted) = preTMX.whitelistConfig(user1);
        assertFalse(fromWhitelisted);
        assertFalse(toWhitelisted);
    }

    function test_UpdateWhitelist() public {
        // Setup: whitelist user1 for from only
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user1, true, false);

        // Execute: update to to only
        preTMX.whitelistTransfer(user1, false, true);
        vm.stopPrank();

        // Assert
        (bool fromWhitelisted, bool toWhitelisted) = preTMX.whitelistConfig(user1);
        assertFalse(fromWhitelisted);
        assertTrue(toWhitelisted);
    }

    // ========== Events Tests ==========

    function test_TransferEnabledEvent() public {
        vm.expectEmit(true, true, true, true);
        emit TransferEnabled(true);

        vm.prank(admin);
        preTMX.enableTransfer();
    }

    function test_TransferDisabledEvent() public {
        vm.startPrank(admin);
        preTMX.enableTransfer();

        vm.expectEmit(true, true, true, true);
        emit TransferEnabled(false);

        preTMX.disableTransfer();
        vm.stopPrank();
    }

    function test_TransferWhitelistedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit TransferWhitelisted(user1, true, false);

        vm.prank(admin);
        preTMX.whitelistTransfer(user1, true, false);
    }

    function test_TransferWhitelistedEvent_OnDeployment() public {
        vm.expectEmit(true, true, true, true);
        emit TransferWhitelisted(user1, true, true);

        vm.prank(user1);
        new PreTMX(user1);
    }

    // ========== Edge Cases ==========

    function test_AdminCanAlwaysTransferWhenDisabled() public view {
        // Admin is whitelisted by default, so can transfer even when disabled
        assertEq(preTMX.transferEnabled(), false);
        (bool fromWhitelisted, bool toWhitelisted) = preTMX.whitelistConfig(admin);
        assertTrue(fromWhitelisted);
        assertTrue(toWhitelisted);
    }

    function test_TransferToSelf_NonWhitelisted_WhenDisabled_Reverts() public {
        // Setup: Give user1 some tokens
        vm.prank(admin);
        preTMX.transfer(user1, TRANSFER_AMOUNT);

        // Execute & Assert: Even transfer to self should fail if not whitelisted
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferNotWhitelisted.selector, user1, user1));
        preTMX.transfer(user1, TRANSFER_AMOUNT);
    }

    function test_TransferToSelf_Whitelisted_Succeeds() public {
        // Setup
        vm.startPrank(admin);
        preTMX.whitelistTransfer(user1, true, false);
        preTMX.transfer(user1, TRANSFER_AMOUNT);
        vm.stopPrank();

        // Execute: Transfer to self
        vm.prank(user1);
        preTMX.transfer(user1, TRANSFER_AMOUNT);

        // Assert
        assertEq(preTMX.balanceOf(user1), TRANSFER_AMOUNT);
    }

    function test_ZeroTransfer_FollowsWhitelistRules() public {
        // Setup: Give user1 some tokens
        vm.prank(admin);
        preTMX.transfer(user1, TRANSFER_AMOUNT);

        // Execute & Assert: Even 0 amount transfer should follow whitelist rules
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferNotWhitelisted.selector, user1, user2));
        preTMX.transfer(user2, 0);
    }

    function test_MultipleEnableDisableCycles() public {
        vm.startPrank(admin);

        preTMX.enableTransfer();
        assertTrue(preTMX.transferEnabled());

        preTMX.disableTransfer();
        assertFalse(preTMX.transferEnabled());

        preTMX.enableTransfer();
        assertTrue(preTMX.transferEnabled());

        preTMX.disableTransfer();
        assertFalse(preTMX.transferEnabled());

        vm.stopPrank();
    }
}
