// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PreTMX} from "../../contracts/tokenomics/PreTMX.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract PreTMXTest is Test {
    PreTMX public preTMX;
    address public admin;
    address public user1;
    address public user2;
    uint256 public initialSupply = 1e9 ether;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

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
        assertTrue(preTMX.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(preTMX.isTransferredFromWhitelisted(admin));
        assertTrue(preTMX.isTransferredToWhitelisted(admin));
    }

    function test_EnableTransfer() public {
        vm.prank(admin);
        preTMX.enableTransfer();
        assertFalse(preTMX.transferRestricted());
    }

    function test_DisableTransfer() public {
        vm.startPrank(admin);
        preTMX.enableTransfer();
        assertFalse(preTMX.transferRestricted());

        preTMX.disableTransfer();
        assertTrue(preTMX.transferRestricted());
        vm.stopPrank();
    }

    function test_EnableTransfer_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, DEFAULT_ADMIN_ROLE)
        );
        preTMX.enableTransfer();
    }

    function test_DisableTransfer_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, DEFAULT_ADMIN_ROLE)
        );
        preTMX.disableTransfer();
    }

    function test_Transfer_WhenRestricted_NotWhitelisted() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferToNotWhitelisted.selector, user1));
        preTMX.transfer(user1, 1000);
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

    function test_TransferFrom_WhenRestricted_NotWhitelisted() public {
        vm.prank(admin);
        preTMX.approve(user1, 1000);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferToNotWhitelisted.selector, user2));
        preTMX.transferFrom(admin, user2, 1000);
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
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, DEFAULT_ADMIN_ROLE)
        );
        preTMX.mint(user1, 5000);
    }

    function test_Burn_WhenRestricted() public {
        // First give some tokens to user1 via minting (bypasses restrictions)
        vm.prank(admin);
        preTMX.mint(user1, 5000);

        vm.prank(user1);

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(user1, address(0), 2000);

        preTMX.burn(2000);

        assertEq(preTMX.balanceOf(user1), 3000);
        assertEq(preTMX.totalSupply(), initialSupply + 5000 - 2000);
    }

    function test_Burn_WhenNotRestricted() public {
        // First give some tokens to user1
        vm.startPrank(admin);
        preTMX.enableTransfer();
        preTMX.transfer(user1, 5000);
        vm.stopPrank();

        vm.prank(user1);

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(user1, address(0), 2000);

        preTMX.burn(2000);

        assertEq(preTMX.balanceOf(user1), 3000);
        assertEq(preTMX.totalSupply(), initialSupply - 2000);
    }

    function test_Burn_InsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user1, 0, 1));
        preTMX.burn(1);
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
        vm.assume(to != address(0));
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
        assertTrue(preTMX.isTransferredToWhitelisted(admin));

        // Other users should not be whitelisted
        assertFalse(preTMX.isTransferredFromWhitelisted(user1));
        assertFalse(preTMX.isTransferredToWhitelisted(user1));
    }

    function test_WhitelistTransferFrom() public {
        // Initially user1 is not whitelisted
        assertFalse(preTMX.isTransferredFromWhitelisted(user1));

        // Admin whitelists user1 for sending
        vm.prank(admin);
        preTMX.whitelistTransferFrom(user1, true);

        assertTrue(preTMX.isTransferredFromWhitelisted(user1));
    }

    function test_WhitelistTransferFrom_Unwhitelist() public {
        // First whitelist user1
        vm.startPrank(admin);
        preTMX.whitelistTransferFrom(user1, true);
        assertTrue(preTMX.isTransferredFromWhitelisted(user1));

        // Then unwhitelist user1
        preTMX.whitelistTransferFrom(user1, false);
        assertFalse(preTMX.isTransferredFromWhitelisted(user1));
        vm.stopPrank();
    }

    function test_WhitelistTransferFrom_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, DEFAULT_ADMIN_ROLE)
        );
        preTMX.whitelistTransferFrom(user2, true);
    }

    function test_WhitelistTransferTo() public {
        // Initially user1 is not whitelisted
        assertFalse(preTMX.isTransferredToWhitelisted(user1));

        // Admin whitelists user1 for receiving
        vm.prank(admin);
        preTMX.whitelistTransferTo(user1, true);

        assertTrue(preTMX.isTransferredToWhitelisted(user1));
    }

    function test_WhitelistTransferTo_Unwhitelist() public {
        // First whitelist user1
        vm.startPrank(admin);
        preTMX.whitelistTransferTo(user1, true);
        assertTrue(preTMX.isTransferredToWhitelisted(user1));

        // Then unwhitelist user1
        preTMX.whitelistTransferTo(user1, false);
        assertFalse(preTMX.isTransferredToWhitelisted(user1));
        vm.stopPrank();
    }

    function test_WhitelistTransferTo_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, DEFAULT_ADMIN_ROLE)
        );
        preTMX.whitelistTransferTo(user2, true);
    }

    function test_WhitelistTransferTo_EnablesTransfer() public {
        // Whitelist user1 to receive tokens
        vm.startPrank(admin);
        preTMX.whitelistTransferTo(user1, true);

        // Now admin can transfer to user1 even when restricted
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(admin, user1, 1000);

        bool success = preTMX.transfer(user1, 1000);
        assertTrue(success);
        assertEq(preTMX.balanceOf(user1), 1000);
        vm.stopPrank();
    }

    function test_WhitelistTransferFrom_EnablesTransfer() public {
        // Give tokens to user1 via minting and whitelist user1 to send
        vm.startPrank(admin);
        preTMX.mint(user1, 1000);
        preTMX.whitelistTransferFrom(user1, true);
        preTMX.whitelistTransferTo(admin, true); // admin already whitelisted but being explicit
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
        preTMX.whitelistTransferFrom(user1, true);
        preTMX.whitelistTransferTo(user2, true);
        vm.stopPrank();

        // Now user1 can transfer to user2
        vm.prank(user1);
        bool success = preTMX.transfer(user2, 300);
        assertTrue(success);
        assertEq(preTMX.balanceOf(user1), 700);
        assertEq(preTMX.balanceOf(user2), 300);
    }

    function test_PartialWhitelisting_StillRestricted() public {
        // Only whitelist user1 to send, but not user2 to receive
        vm.startPrank(admin);
        preTMX.mint(user1, 1000);
        preTMX.whitelistTransferFrom(user1, true);
        // user2 is not whitelisted to receive
        vm.stopPrank();

        // Transfer should still fail because user2 is not whitelisted to receive
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferToNotWhitelisted.selector, user2));
        preTMX.transfer(user2, 500);
    }

    function test_WhitelistTransferFrom_WithTransferFrom() public {
        // Test whitelisting with transferFrom function
        vm.startPrank(admin);
        preTMX.mint(user1, 1000);
        preTMX.whitelistTransferFrom(user1, true);
        preTMX.whitelistTransferTo(user2, true);
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
        preTMX.whitelistTransferTo(user2, true);
        vm.stopPrank();

        // Verify transfer works
        vm.prank(user1);
        preTMX.transfer(user2, 100);
        assertEq(preTMX.balanceOf(user2), 100);

        // Now unwhitelist user1 from sending
        vm.prank(admin);
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

    function test_RestrictedTransfer_ToNotWhitelisted() public {
        // Admin tries to transfer to non-whitelisted user1 - should fail
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferToNotWhitelisted.selector, user1));
        preTMX.transfer(user1, 1000);
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

        // Burn from non-whitelisted user should work
        vm.prank(user1);
        preTMX.burn(500);
        assertEq(preTMX.balanceOf(user1), 500);
    }

    function test_FuzzWhitelisting(address user, bool fromWhitelisted, bool toWhitelisted) public {
        vm.assume(user != address(0) && user != admin);

        vm.startPrank(admin);
        preTMX.whitelistTransferFrom(user, fromWhitelisted);
        preTMX.whitelistTransferTo(user, toWhitelisted);
        vm.stopPrank();

        assertEq(preTMX.isTransferredFromWhitelisted(user), fromWhitelisted);
        assertEq(preTMX.isTransferredToWhitelisted(user), toWhitelisted);
    }

    function test_WhitelistSelf() public {
        // Test admin whitelisting themselves (should work but redundant since already whitelisted)
        vm.startPrank(admin);
        preTMX.whitelistTransferFrom(admin, false);
        preTMX.whitelistTransferTo(admin, false);

        assertFalse(preTMX.isTransferredFromWhitelisted(admin));
        assertFalse(preTMX.isTransferredToWhitelisted(admin));

        // Re-whitelist admin
        preTMX.whitelistTransferFrom(admin, true);
        preTMX.whitelistTransferTo(admin, true);

        assertTrue(preTMX.isTransferredFromWhitelisted(admin));
        assertTrue(preTMX.isTransferredToWhitelisted(admin));
        vm.stopPrank();
    }

    function test_RestrictedTransferFrom_ToNotWhitelisted() public {
        // Test transferFrom with non-whitelisted recipient
        vm.startPrank(admin);
        preTMX.mint(user1, 1000);
        preTMX.whitelistTransferFrom(user1, true); // whitelist sender but not recipient
        vm.stopPrank();

        vm.prank(user1);
        preTMX.approve(admin, 500);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferToNotWhitelisted.selector, user2));
        preTMX.transferFrom(user1, user2, 500);
    }

    function test_BothErrorTypes() public {
        // Test that we get from error when sender not whitelisted
        vm.prank(admin);
        preTMX.mint(user1, 1000);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferFromNotWhitelisted.selector, user1));
        preTMX.transfer(user2, 500);

        // Test that we get to error when recipient not whitelisted (sender is whitelisted)
        vm.prank(admin);
        preTMX.whitelistTransferFrom(user1, true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PreTMX.TransferToNotWhitelisted.selector, user2));
        preTMX.transfer(user2, 500);
    }
}
