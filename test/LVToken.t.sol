// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LVToken.sol";

contract LVTokenTest is Test {
    LVToken token;
    address owner = address(this);
    address vault = address(0x1234);
    address admin = 0x64ec61145EC91F2F6370AAbDF977cE359748e507;
    address unauthorized = address(0x9999);

    function setUp() public {
        token = new LVToken("Test Token", "TT");
    }

    // --- Allowlist Tests ---

    function test_ownerCanSetAllowed() public {
        token.setAllowed(vault, true);
        assertTrue(token.allowed(vault));
    }

    function test_nonOwnerCannotSetAllowed() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        token.setAllowed(vault, true);
    }

    function test_allowedAddressCanMint() public {
        token.setAllowed(vault, true);
        vm.prank(vault);
        bool success = token.mint(address(0x5555), 100e18);
        assertTrue(success);
        assertEq(token.balanceOf(address(0x5555)), 100e18);
    }

    function test_ownerCanMint() public {
        bool success = token.mint(address(0x5555), 100e18);
        assertTrue(success);
    }

    function test_unauthorizedCannotMint() public {
        vm.prank(unauthorized);
        vm.expectRevert("Not allowed");
        token.mint(address(0x5555), 100e18);
    }

    function test_allowedAddressCanBurn() public {
        token.setAllowed(vault, true);
        // Mint first
        token.mint(address(0x5555), 100e18);
        // Burn via allowed
        vm.prank(vault);
        bool success = token.burn(address(0x5555), 50e18);
        assertTrue(success);
        assertEq(token.balanceOf(address(0x5555)), 50e18);
    }

    function test_unauthorizedCannotBurn() public {
        token.mint(address(0x5555), 100e18);
        vm.prank(unauthorized);
        vm.expectRevert("Not allowed");
        token.burn(address(0x5555), 50e18);
    }

    function test_revokeAllowedAddress() public {
        token.setAllowed(vault, true);
        token.setAllowed(vault, false);
        vm.prank(vault);
        vm.expectRevert("Not allowed");
        token.mint(address(0x5555), 100e18);
    }

    function test_multipleAllowedAddresses() public {
        token.setAllowed(vault, true);
        token.setAllowed(admin, true);

        vm.prank(vault);
        token.mint(address(0x5555), 50e18);

        vm.prank(admin);
        token.mint(address(0x5555), 50e18);

        assertEq(token.balanceOf(address(0x5555)), 100e18);
    }

    function test_adminCanRevokeOwnAccess() public {
        token.setAllowed(admin, true);
        // Transfer ownership to admin
        token.transferOwnership(admin);
        // Admin revokes self from allowlist
        vm.prank(admin);
        token.setAllowed(admin, false);
        assertFalse(token.allowed(admin));
        // Admin can still mint because they are owner
        // To fully lose access, they'd need to renounce ownership too
        vm.prank(admin);
        bool success = token.mint(address(0x5555), 100e18);
        assertTrue(success);
        // Now renounce ownership — admin loses all access
        vm.prank(admin);
        token.renounceOwnership();
        vm.prank(admin);
        vm.expectRevert("Not allowed");
        token.mint(address(0x5555), 100e18);
    }

    function test_ownerCanRenounceOwnership() public {
        token.setAllowed(vault, true);
        token.renounceOwnership();
        // Vault can still mint (allowed)
        vm.prank(vault);
        token.mint(address(0x5555), 100e18);
        assertEq(token.balanceOf(address(0x5555)), 100e18);
        // But nobody can add new allowed addresses
        vm.expectRevert();
        token.setAllowed(address(0x7777), true);
    }
}
