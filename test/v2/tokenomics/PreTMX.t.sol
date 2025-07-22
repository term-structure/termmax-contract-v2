// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PreTMX} from "contracts/v2/tokenomics/PreTMX.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract PreTMXTest is Test {
    PreTMX public preTMX;
    address public admin;
    address public user1;
    address public user2;
    uint256 public initialSupply = 1e9 ether;

    function setUp() public {
        admin = address(1);
        user1 = address(2);
        user2 = address(3);

        vm.startPrank(admin);
        preTMX = new PreTMX(admin);
        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(preTMX.name(), "Pre TermMax Token");
        assertEq(preTMX.symbol(), "pTMX");
        assertEq(preTMX.totalSupply(), initialSupply);
        assertEq(preTMX.balanceOf(admin), initialSupply);
        assertTrue(preTMX.transferRestricted());
        assertEq(preTMX.owner(), admin);
        assertTrue(preTMX.isTransferredFromWhitelisted(admin));
    }

    function test_EnableTransfer() public {
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferRestricted(false);

        preTMX.enableTransfer();
        assertFalse(preTMX.transferRestricted());
    }

    function test_DisableTransfer() public {
        vm.startPrank(admin);
        preTMX.enableTransfer();
        assertFalse(preTMX.transferRestricted());

        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferRestricted(true);

        preTMX.disableTransfer();
        assertTrue(preTMX.transferRestricted());
        vm.stopPrank();
    }

    function test_EnableTransfer_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.enableTransfer();
    }

    function test_DisableTransfer_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.disableTransfer();
    }

    function test_Transfer_WhenRestricted_AdminWhitelisted() public {
        // Admin can transfer to another admin (both whitelisted)
        vm.prank(admin);

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(admin, admin, 1000);

        bool success = preTMX.transfer(admin, 1000);
        assertTrue(success);
        assertEq(preTMX.balanceOf(admin), initialSupply); // Same balance since transferring to self
    }

    function test_Transfer_WhenNotRestricted() public {
        vm.startPrank(admin);
        preTMX.enableTransfer();

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(admin, user1, 1000);

        bool success = preTMX.transfer(user1, 1000);
        assertTrue(success);
        assertEq(preTMX.balanceOf(user1), 1000);
        assertEq(preTMX.balanceOf(admin), initialSupply - 1000);
        vm.stopPrank();
    }

    function test_TransferFrom_WhenNotRestricted() public {
        vm.startPrank(admin);
        preTMX.enableTransfer();
        preTMX.approve(user1, 1000);
        vm.stopPrank();

        vm.prank(user1);
        bool success = preTMX.transferFrom(admin, user2, 1000);

        assertTrue(success);
        assertEq(preTMX.balanceOf(user2), 1000);
        assertEq(preTMX.balanceOf(admin), initialSupply - 1000);
    }

    function test_TransferFrom_WhenRestricted_AdminToAdmin() public {
        vm.startPrank(admin);
        preTMX.approve(admin, 1000);

        bool success = preTMX.transferFrom(admin, admin, 1000);
        assertTrue(success);
        assertEq(preTMX.balanceOf(admin), initialSupply); // Same balance since transferring to self
        vm.stopPrank();
    }

    function test_Mint_WhenRestricted() public {
        // Minting should work even when transfers are restricted
        vm.prank(admin);

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), user1, 5000);

        preTMX.mint(user1, 5000);

        assertEq(preTMX.balanceOf(user1), 5000);
        assertEq(preTMX.totalSupply(), initialSupply + 5000);
    }

    function test_Mint_WhenNotRestricted() public {
        vm.startPrank(admin);
        preTMX.enableTransfer();

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), user1, 5000);

        preTMX.mint(user1, 5000);

        assertEq(preTMX.balanceOf(user1), 5000);
        assertEq(preTMX.totalSupply(), initialSupply + 5000);
        vm.stopPrank();
    }

    function test_Mint_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.mint(user1, 5000);
    }

    function test_Burn_WhenRestricted() public {
        // First give some tokens to user1 via minting (bypasses restrictions)
        vm.prank(admin);
        preTMX.mint(user1, 5000);

        // Only admin (owner) can burn tokens, not user1
        vm.prank(admin);

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(admin, address(0), 2000);

        preTMX.burn(2000);

        assertEq(preTMX.balanceOf(admin), initialSupply - 2000);
        assertEq(preTMX.totalSupply(), initialSupply + 5000 - 2000);
    }

    function test_Burn_WhenNotRestricted() public {
        // First transfer some tokens to user1
        vm.startPrank(admin);
        preTMX.enableTransfer();
        preTMX.transfer(user1, 5000);

        // Only admin (owner) can burn tokens
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(admin, address(0), 2000);

        preTMX.burn(2000);

        assertEq(preTMX.balanceOf(admin), initialSupply - 5000 - 2000);
        assertEq(preTMX.totalSupply(), initialSupply - 2000);
        vm.stopPrank();
    }

    function test_Burn_InsufficientBalance() public {
        // Admin tries to burn more than they have
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, admin, initialSupply, initialSupply + 1
            )
        );
        preTMX.burn(initialSupply + 1);
    }

    function test_Burn_NotOwner() public {
        // Give tokens to user1 via minting
        vm.prank(admin);
        preTMX.mint(user1, 1000);

        // user1 tries to burn but should fail because only owner can burn
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.burn(500);
    }

    function test_FuzzTransfer_WhenNotRestricted(uint256 amount) public {
        // Bound the amount to a reasonable range to avoid overflow issues
        amount = bound(amount, 1, initialSupply);

        vm.startPrank(admin);
        preTMX.enableTransfer();
        bool success = preTMX.transfer(user1, amount);
        vm.stopPrank();

        assertTrue(success);
        assertEq(preTMX.balanceOf(user1), amount);
        assertEq(preTMX.balanceOf(admin), initialSupply - amount);
    }

    function test_FuzzMint(address to, uint256 amount) public {
        // Avoid minting to zero address and zero amount
        vm.assume(to != address(0) && to != admin);
        amount = bound(amount, 1, type(uint256).max - initialSupply);

        vm.prank(admin);
        preTMX.mint(to, amount);

        assertEq(preTMX.balanceOf(to), amount);
        assertEq(preTMX.totalSupply(), initialSupply + amount);
    }

    // Additional tests for whitelisting functionality
    function test_WhitelistingState() public {
        // Admin should be whitelisted by default
        assertTrue(preTMX.isTransferredFromWhitelisted(admin));

        // Other users should not be whitelisted
        assertFalse(preTMX.isTransferredFromWhitelisted(user1));
    }

    function test_WhitelistTransferFrom() public {
        // Initially user1 is not whitelisted
        assertFalse(preTMX.isTransferredFromWhitelisted(user1));

        // Admin whitelists user1 for sending
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferFromWhitelisted(user1, true);

        preTMX.whitelistTransferFrom(user1, true);

        assertTrue(preTMX.isTransferredFromWhitelisted(user1));
    }

    function test_WhitelistTransferFrom_Unwhitelist() public {
        // First whitelist user1
        vm.startPrank(admin);
        preTMX.whitelistTransferFrom(user1, true);
        assertTrue(preTMX.isTransferredFromWhitelisted(user1));

        // Then unwhitelist user1
        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferFromWhitelisted(user1, false);

        preTMX.whitelistTransferFrom(user1, false);
        assertFalse(preTMX.isTransferredFromWhitelisted(user1));
        vm.stopPrank();
    }

    function test_WhitelistTransferFrom_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.whitelistTransferFrom(user2, true);
    }

    function test_WhitelistTransferFrom_EnablesTransfer() public {
        // Give tokens to user1 via minting and whitelist user1 to send
        vm.startPrank(admin);
        preTMX.mint(user1, 1000);

        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferFromWhitelisted(user1, true);

        preTMX.whitelistTransferFrom(user1, true);
        vm.stopPrank();

        // Now user1 can transfer to admin
        vm.prank(user1);
        bool success = preTMX.transfer(admin, 500);
        assertTrue(success);
        assertEq(preTMX.balanceOf(user1), 500);
        assertEq(preTMX.balanceOf(admin), initialSupply + 500);
    }

    function test_BothWhitelisted_EnablesTransfer() public {
        // Whitelist both user1 and user2
        vm.startPrank(admin);
        preTMX.mint(user1, 1000);

        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferFromWhitelisted(user1, true);

        preTMX.whitelistTransferFrom(user1, true);
        vm.stopPrank();

        // Now user1 can transfer to user2
        vm.prank(user1);
        bool success = preTMX.transfer(user2, 300);
        assertTrue(success);
        assertEq(preTMX.balanceOf(user1), 700);
        assertEq(preTMX.balanceOf(user2), 300);
    }

    function test_WhitelistTransferFrom_WithTransferFrom() public {
        // Test whitelisting with transferFrom function
        vm.startPrank(admin);
        preTMX.mint(user1, 1000);

        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferFromWhitelisted(user1, true);

        preTMX.whitelistTransferFrom(user1, true);
        vm.stopPrank();

        // user1 approves admin to spend tokens
        vm.prank(user1);
        preTMX.approve(admin, 500);

        // admin can transfer from user1 to user2
        vm.prank(admin);
        bool success = preTMX.transferFrom(user1, user2, 500);
        assertTrue(success);
        assertEq(preTMX.balanceOf(user1), 500);
        assertEq(preTMX.balanceOf(user2), 500);
    }

    function test_UnwhitelistingBreaksTransfer() public {
        // First set up a working scenario
        vm.startPrank(admin);
        preTMX.mint(user1, 1000);
        preTMX.whitelistTransferFrom(user1, true);
        vm.stopPrank();

        // Verify transfer works
        vm.prank(user1);
        preTMX.transfer(user2, 100);
        assertEq(preTMX.balanceOf(user2), 100);

        // Now unwhitelist user1 from sending
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferFromWhitelisted(user1, false);

        preTMX.whitelistTransferFrom(user1, false);

        // Transfer should now fail
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferFromNotWhitelisted.selector, user1));
        preTMX.transfer(user2, 100);
    }

    function test_RestrictedTransfer_FromNotWhitelisted() public {
        // Give tokens to user1 via minting (bypasses restrictions)
        vm.prank(admin);
        preTMX.mint(user1, 1000);

        // user1 (not whitelisted) tries to transfer - should fail
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferFromNotWhitelisted.selector, user1));
        preTMX.transfer(admin, 500);
    }

    function test_RestrictedTransferFrom_FromNotWhitelisted() public {
        // Give tokens to user1 and approve user2
        vm.prank(admin);
        preTMX.mint(user1, 1000);

        vm.prank(user1);
        preTMX.approve(user2, 500);

        // user2 tries to transfer from user1 (not whitelisted) - should fail
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferFromNotWhitelisted.selector, user1));
        preTMX.transferFrom(user1, admin, 500);
    }

    function test_MintAndBurnBypassRestrictions() public {
        // Verify that minting and burning work even when transfers are restricted
        assertTrue(preTMX.transferRestricted());

        // Mint to non-whitelisted user should work
        vm.prank(admin);
        preTMX.mint(user1, 1000);
        assertEq(preTMX.balanceOf(user1), 1000);

        // Only owner can burn tokens (admin in this case)
        vm.prank(admin);
        preTMX.burn(500);
        assertEq(preTMX.balanceOf(admin), initialSupply - 500);
        assertEq(preTMX.totalSupply(), initialSupply + 1000 - 500);
    }

    function test_FuzzWhitelisting(address user, bool fromWhitelisted, bool toWhitelisted) public {
        vm.assume(user != address(0) && user != admin);

        vm.startPrank(admin);
        preTMX.whitelistTransferFrom(user, fromWhitelisted);
        vm.stopPrank();

        assertEq(preTMX.isTransferredFromWhitelisted(user), fromWhitelisted);
    }

    function test_WhitelistSelf() public {
        // Test admin whitelisting themselves (should work but redundant since already whitelisted)
        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferFromWhitelisted(admin, false);

        preTMX.whitelistTransferFrom(admin, false);

        assertFalse(preTMX.isTransferredFromWhitelisted(admin));

        // Re-whitelist admin
        vm.expectEmit(true, true, true, true);
        emit PreTMX.TransferFromWhitelisted(admin, true);

        preTMX.whitelistTransferFrom(admin, true);

        assertTrue(preTMX.isTransferredFromWhitelisted(admin));
        vm.stopPrank();
    }

    // ============ Ownership Transfer Tests ============

    function test_InitialOwnership() public {
        assertEq(preTMX.owner(), admin);
        assertEq(preTMX.pendingOwner(), address(0));
    }

    function test_TransferOwnership() public {
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit Ownable2Step.OwnershipTransferStarted(admin, user1);

        preTMX.transferOwnership(user1);

        // Ownership should not change until accepted
        assertEq(preTMX.owner(), admin);
        assertEq(preTMX.pendingOwner(), user1);
    }

    function test_TransferOwnership_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.transferOwnership(user2);
    }

    function test_AcceptOwnership() public {
        // Start ownership transfer
        vm.prank(admin);
        preTMX.transferOwnership(user1);

        // Accept ownership
        vm.prank(user1);

        vm.expectEmit(true, true, true, true);
        emit Ownable.OwnershipTransferred(admin, user1);

        preTMX.acceptOwnership();

        // Verify ownership has changed
        assertEq(preTMX.owner(), user1);
        assertEq(preTMX.pendingOwner(), address(0));
    }

    function test_AcceptOwnership_NotPendingOwner() public {
        // Start ownership transfer to user1
        vm.prank(admin);
        preTMX.transferOwnership(user1);

        // user2 tries to accept (should fail)
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user2));
        preTMX.acceptOwnership();

        // Ownership should remain unchanged
        assertEq(preTMX.owner(), admin);
        assertEq(preTMX.pendingOwner(), user1);
    }

    function test_AcceptOwnership_NoPendingTransfer() public {
        // Try to accept ownership when no transfer is pending
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.acceptOwnership();
    }

    function test_TransferOwnership_CancelPending() public {
        // Start ownership transfer to user1
        vm.prank(admin);
        preTMX.transferOwnership(user1);
        assertEq(preTMX.pendingOwner(), user1);

        // Cancel by transferring to zero address
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit Ownable2Step.OwnershipTransferStarted(admin, address(0));

        preTMX.transferOwnership(address(0));
        assertEq(preTMX.pendingOwner(), address(0));

        // user1 should no longer be able to accept
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.acceptOwnership();
    }

    function test_TransferOwnership_ReplacePending() public {
        // Start ownership transfer to user1
        vm.prank(admin);
        preTMX.transferOwnership(user1);
        assertEq(preTMX.pendingOwner(), user1);

        // Replace with transfer to user2
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit Ownable2Step.OwnershipTransferStarted(admin, user2);

        preTMX.transferOwnership(user2);
        assertEq(preTMX.pendingOwner(), user2);

        // user1 should no longer be able to accept
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.acceptOwnership();

        // user2 should be able to accept
        vm.prank(user2);
        preTMX.acceptOwnership();
        assertEq(preTMX.owner(), user2);
    }

    function test_RenounceOwnership() public {
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit Ownable.OwnershipTransferred(admin, address(0));

        preTMX.renounceOwnership();

        assertEq(preTMX.owner(), address(0));
        assertEq(preTMX.pendingOwner(), address(0));
    }

    function test_RenounceOwnership_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.renounceOwnership();
    }

    function test_OwnershipTransfer_FunctionalityTransfers() public {
        // Transfer ownership to user1
        vm.prank(admin);
        preTMX.transferOwnership(user1);

        vm.prank(user1);
        preTMX.acceptOwnership();

        // Verify new owner can use onlyOwner functions
        vm.prank(user1);
        preTMX.enableTransfer();
        assertFalse(preTMX.transferRestricted());

        vm.prank(user1);
        preTMX.mint(user2, 1000);
        assertEq(preTMX.balanceOf(user2), 1000);

        vm.prank(user1);
        preTMX.whitelistTransferFrom(user2, true);
        assertTrue(preTMX.isTransferredFromWhitelisted(user2));

        // Verify old owner can no longer use onlyOwner functions
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, admin));
        preTMX.disableTransfer();
    }

    function test_OwnershipTransfer_WithPendingTransfer() public {
        // Start ownership transfer to user1
        vm.prank(admin);
        preTMX.transferOwnership(user1);

        // Verify admin can still use onlyOwner functions while transfer is pending
        vm.prank(admin);
        preTMX.enableTransfer();
        assertFalse(preTMX.transferRestricted());

        // Verify user1 cannot use onlyOwner functions yet
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        preTMX.disableTransfer();

        // Complete the transfer
        vm.prank(user1);
        preTMX.acceptOwnership();

        // Now user1 can use onlyOwner functions
        vm.prank(user1);
        preTMX.disableTransfer();
        assertTrue(preTMX.transferRestricted());
    }

    function test_FuzzOwnershipTransfer(address newOwner) public {
        vm.assume(newOwner != address(0) && newOwner != admin);

        // Transfer ownership
        vm.prank(admin);
        preTMX.transferOwnership(newOwner);
        assertEq(preTMX.pendingOwner(), newOwner);

        // Accept ownership
        vm.prank(newOwner);
        preTMX.acceptOwnership();
        assertEq(preTMX.owner(), newOwner);
        assertEq(preTMX.pendingOwner(), address(0));
    }
}
