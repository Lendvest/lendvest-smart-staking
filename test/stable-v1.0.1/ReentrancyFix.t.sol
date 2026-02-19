// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseStableTest.sol";
import {IMorpho} from "../../src/interfaces/IMorpho.sol";

/**
 * @title ReentrancyFixTest
 * @notice Tests for the reentrancy fix in onMorphoFlashLoan (commit ca12003)
 * @dev Validates that:
 *      1. Flash loan callback works without ReentrantCall error
 *      2. Only Morpho can call the callback
 *      3. _borrowInitiated flag prevents unauthorized calls
 */
contract ReentrancyFixTest is BaseStableTest {
    IMorpho constant morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test that flash loan succeeds without reentrancy error
     * @dev Before fix: ReentrantCall error because callback tried to acquire lock
     * @dev After fix: Callback executes without lock, protected by msg.sender check
     */
    function test_FlashLoanCallbackNoReentrancy() public {
        // Use helper to create balanced orders and start epoch
        _startBalancedEpoch();

        // Verify: Epoch started successfully (flash loan completed)
        assertTrue(vault.epochStarted(), "Epoch should have started");
        assertGt(vault.totalBorrowAmount(), 0, "Should have borrowed");
    }

    /**
     * @notice Test that only Morpho can call onMorphoFlashLoan
     * @dev Direct calls should revert with Unauthorized
     */
    function test_OnlyMorphoCanCallCallback() public {
        bytes memory data = abi.encode(1 ether, 0.5 ether);

        // Attempt direct call from non-Morpho address
        vm.prank(lender1);
        vm.expectRevert(VaultLib.Unauthorized.selector);
        vault.onMorphoFlashLoan(1 ether, data);
    }

    /**
     * @notice Test that callback reverts without _borrowInitiated flag
     * @dev Even Morpho cannot call unless vault initiated the borrow
     */
    function test_CallbackRequiresBorrowInitiated() public {
        bytes memory data = abi.encode(1 ether, 0.5 ether);

        // Attempt call from Morpho without borrow being initiated
        vm.prank(address(morpho));
        vm.expectRevert(VaultLib.Unauthorized.selector);
        vault.onMorphoFlashLoan(1 ether, data);
    }

    /**
     * @notice Test epoch can start successfully (single epoch simplified test)
     * @dev Ensures the fix works for epoch starting
     */
    function test_EpochStartsSuccessfully() public {
        // Use helper for balanced orders
        _startBalancedEpoch();

        assertTrue(vault.epochStarted(), "Epoch should start");
        assertGt(vault.totalBorrowAmount(), 0, "Should have borrowed amount");
    }
}
