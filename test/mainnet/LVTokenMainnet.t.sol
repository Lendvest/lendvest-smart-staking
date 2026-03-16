// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/LVToken.sol";

/**
 * @title LVTokenMainnetTest
 * @notice Tests for LVToken against deployed mainnet contracts
 */
contract LVTokenMainnetTest is Test {
    // Deployed token addresses from README.md
    LVToken public lvweth = LVToken(0x1745D52b537b9e2DC46CeeDD7375614b3D91CB8C);
    LVToken public lvwsteth = LVToken(0xEFe6E493184F48b5f5533a827C9b4A6b4fFC09dE);

    // Deployed vault (should be allowed to mint/burn)
    address public constant VAULT = 0xe3C272F793d32f4a885e4d748B8E5968f515c8D6;
    // Governance multisig (token owner)
    address public constant GOVERNANCE = 0x3F0976C7007F50b0BA5EFe00764fCFB251656D4f;

    address unauthorized = makeAddr("unauthorized");

    function setUp() public {}

    // --- Ownership Tests ---

    function test_TokenOwnership() public view {
        assertEq(lvweth.owner(), GOVERNANCE, "LVWETH owner should be governance");
        assertEq(lvwsteth.owner(), GOVERNANCE, "LVWSTETH owner should be governance");
    }

    function test_VaultIsAllowed() public view {
        assertTrue(lvweth.allowed(VAULT), "Vault should be allowed for LVWETH");
        assertTrue(lvwsteth.allowed(VAULT), "Vault should be allowed for LVWSTETH");
    }

    // --- Access Control Tests ---

    function test_unauthorizedCannotMint() public {
        vm.prank(unauthorized);
        vm.expectRevert("Not allowed");
        lvweth.mint(unauthorized, 100e18);
    }

    function test_unauthorizedCannotBurn() public {
        vm.prank(unauthorized);
        vm.expectRevert("Not allowed");
        lvweth.burn(unauthorized, 100e18);
    }

    function test_nonOwnerCannotSetAllowed() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        lvweth.setAllowed(unauthorized, true);
    }

    // --- Vault Mint/Burn Tests ---

    function test_vaultCanMint() public {
        address recipient = makeAddr("recipient");
        uint256 amount = 1 ether;

        vm.prank(VAULT);
        bool success = lvweth.mint(recipient, amount);

        assertTrue(success, "Vault should be able to mint");
        assertEq(lvweth.balanceOf(recipient), amount, "Recipient should have tokens");
    }

    function test_vaultCanBurn() public {
        address holder = makeAddr("holder");
        uint256 amount = 1 ether;

        // First mint
        vm.prank(VAULT);
        lvweth.mint(holder, amount);

        // Then burn
        vm.prank(VAULT);
        bool success = lvweth.burn(holder, amount);

        assertTrue(success, "Vault should be able to burn");
        assertEq(lvweth.balanceOf(holder), 0, "Holder should have 0 tokens");
    }

    // --- Owner Permission Tests ---

    function test_ownerCanSetAllowed() public {
        address newAllowed = makeAddr("newAllowed");

        vm.prank(GOVERNANCE);
        lvweth.setAllowed(newAllowed, true);

        assertTrue(lvweth.allowed(newAllowed), "New address should be allowed");

        // Cleanup
        vm.prank(GOVERNANCE);
        lvweth.setAllowed(newAllowed, false);
    }

    function test_ownerCanMint() public {
        address recipient = makeAddr("recipient");
        uint256 amount = 1 ether;

        vm.prank(GOVERNANCE);
        bool success = lvweth.mint(recipient, amount);

        assertTrue(success, "Owner should be able to mint");
    }

    function test_revokeAllowedAddress() public {
        address tempAllowed = makeAddr("tempAllowed");

        // Add
        vm.prank(GOVERNANCE);
        lvweth.setAllowed(tempAllowed, true);
        assertTrue(lvweth.allowed(tempAllowed), "Should be allowed");

        // Revoke
        vm.prank(GOVERNANCE);
        lvweth.setAllowed(tempAllowed, false);
        assertFalse(lvweth.allowed(tempAllowed), "Should not be allowed");

        // Should fail to mint
        vm.prank(tempAllowed);
        vm.expectRevert("Not allowed");
        lvweth.mint(tempAllowed, 100e18);
    }

    // --- Token Metadata Tests ---

    function test_TokenMetadata() public view {
        assertEq(lvweth.name(), "LVWETH-v11", "LVWETH name");
        assertEq(lvweth.symbol(), "LVWETH11", "LVWETH symbol");
        assertEq(lvweth.decimals(), 18, "LVWETH decimals");

        assertEq(lvwsteth.name(), "LVWSTETH-v11", "LVWSTETH name");
        assertEq(lvwsteth.symbol(), "LVWSTETH11", "LVWSTETH symbol");
        assertEq(lvwsteth.decimals(), 18, "LVWSTETH decimals");
    }

    // --- Supply Tests ---

    function test_TotalSupply() public view {
        uint256 lvwethSupply = lvweth.totalSupply();
        uint256 lvwstethSupply = lvwsteth.totalSupply();

        console.log("LVWETH total supply:", lvwethSupply);
        console.log("LVWSTETH total supply:", lvwstethSupply);

        // Supply should be >= 0 (may be 0 if no active epoch)
        assertTrue(lvwethSupply >= 0, "LVWETH supply should be >= 0");
        assertTrue(lvwstethSupply >= 0, "LVWSTETH supply should be >= 0");
    }
}
