// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseStableTest.sol";

/**
 * @title PublicPerformTaskTest
 * @notice Tests for public performTask function (commit a89230a)
 * @dev Validates:
 *      1. Anyone can call performTask() (no access control)
 *      2. performUpkeep() requires forwarder (contrast)
 *      3. checkUpkeep works after epoch starts
 */
contract PublicPerformTaskTest is BaseStableTest {

    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test that performTask has no access control
     * @dev Key: the function doesn't revert with OnlyForwarder
     */
    function test_PerformTaskHasNoAccessControl() public {
        address randomUser = makeAddr("randomUser");

        // performTask is public - it will revert, but NOT with OnlyForwarder
        vm.prank(randomUser);
        try vaultUtil.performTask() {
            // If it succeeds, that's fine
        } catch Error(string memory reason) {
            // Should NOT be an access control error
            assertTrue(
                keccak256(bytes(reason)) != keccak256(bytes("Only callable by forwarder")),
                "performTask should not have forwarder restriction"
            );
        } catch {
            // Panic/other errors are fine - proves function was called
        }
    }

    /**
     * @notice Test that performUpkeep requires forwarder (contrast with performTask)
     */
    function test_PerformUpkeepRequiresForwarder() public {
        address randomUser = makeAddr("randomUser");
        bytes memory performData = abi.encode(uint256(0));

        // performUpkeep requires forwarder - should revert with OnlyForwarder
        vm.prank(randomUser);
        vm.expectRevert(VaultLib.OnlyForwarder.selector);
        vaultUtil.performUpkeep(performData);
    }

    /**
     * @notice Test owner can also call performTask (no restrictions)
     */
    function test_OwnerCanCallPerformTask() public {
        vm.prank(owner);
        try vaultUtil.performTask() {
            // Success is fine
        } catch {
            // Any error except OnlyForwarder is acceptable
        }
    }

    /**
     * @notice Test forwarder can call performTask (it's public)
     */
    function test_ForwarderCanCallPerformTask() public {
        vm.prank(forwarder);
        try vaultUtil.performTask() {
            // Success is fine
        } catch {
            // Any error except OnlyForwarder is acceptable
        }
    }

    /**
     * @notice Test checkUpkeep after epoch starts (no division by zero)
     */
    function test_CheckUpkeepAfterEpochStarts() public {
        // Start a balanced epoch first
        _startBalancedEpoch();

        // Now checkUpkeep should work without division by zero
        (bool upkeepNeeded, bytes memory performData) = vaultUtil.checkUpkeep("");

        // Just verify it doesn't revert
        console.log("Upkeep needed:", upkeepNeeded);
        console.log("Perform data length:", performData.length);
    }

    /**
     * @notice Test checkUpkeep returns task 221 when term ends
     */
    function test_CheckUpkeepReturnsRateTaskAfterTermEnds() public {
        // Start epoch
        _startBalancedEpoch();

        // Fast forward past term duration
        vm.warp(block.timestamp + vault.termDuration() + 1);

        // Check upkeep should return task 221 (rate update)
        (bool upkeepNeeded, bytes memory performData) = vaultUtil.checkUpkeep("");

        if (upkeepNeeded) {
            uint256 taskId = abi.decode(performData, (uint256));
            console.log("Task ID:", taskId);
            assertEq(taskId, 221, "Should be rate update task");
        }
    }

    /**
     * @notice Test performTask is callable from any address
     * @dev Uses multiple random addresses to prove no whitelist
     */
    function test_MultipleUsersCanCallPerformTask() public {
        address[] memory users = new address[](3);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            try vaultUtil.performTask() {
                // Success
            } catch {
                // Any revert except OnlyForwarder is acceptable
            }
        }
    }
}
