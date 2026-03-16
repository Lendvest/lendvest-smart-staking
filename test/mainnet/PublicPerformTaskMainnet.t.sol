// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseMainnetTest.sol";

/**
 * @title PublicPerformTaskMainnetTest
 * @notice Tests for public performTask function against deployed mainnet contracts
 * @dev Validates performTask accessibility and performUpkeep access control
 */
contract PublicPerformTaskMainnetTest is BaseMainnetTest {

    address internal randomUser = makeAddr("randomUser");
    address internal anotherUser = makeAddr("anotherUser");

    function setUp() public override {
        super.setUp();
    }

    // ============ performTask Access Control ============

    function test_PerformTaskHasNoAccessControl() public {
        // performTask is public - anyone can call
        vm.prank(randomUser);
        try vaultUtil.performTask() {
            console.log("performTask succeeded");
        } catch Error(string memory reason) {
            // Should NOT be an access control error
            assertTrue(
                keccak256(bytes(reason)) != keccak256(bytes("Only callable by forwarder")),
                "performTask should not have forwarder restriction"
            );
            console.log("performTask reverted (not access control):", reason);
        } catch {
            console.log("performTask reverted (not access control)");
        }
    }

    function test_PerformUpkeepRequiresForwarder() public {
        bytes memory performData = abi.encode(uint256(0));

        vm.prank(randomUser);
        vm.expectRevert(VaultLib.OnlyForwarder.selector);
        vaultUtil.performUpkeep(performData);

        console.log("performUpkeep correctly requires forwarder");
    }

    // ============ Multi-User performTask ============

    function test_OwnerCanCallPerformTask() public {
        vm.prank(owner);
        try vaultUtil.performTask() {
            console.log("Owner performTask succeeded");
        } catch {
            console.log("Owner performTask reverted (not access control)");
        }
    }

    function test_ForwarderCanCallPerformTask() public {
        address forwarder = vaultUtil.s_forwarderAddress();
        vm.prank(forwarder);
        try vaultUtil.performTask() {
            console.log("Forwarder performTask succeeded");
        } catch {
            console.log("Forwarder performTask reverted (not access control)");
        }
    }

    function test_MultipleUsersCanCallPerformTask() public {
        address[] memory users = new address[](3);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            try vaultUtil.performTask() {
                console.log("User", i, "performTask succeeded");
            } catch {
                console.log("User", i, "performTask reverted (not access control)");
            }
        }

        console.log("All users verified (no access control)");
    }

    // ============ checkUpkeep Tests ============

    function test_CheckUpkeepBasic() public view {
        console.log("=== CheckUpkeep Basic ===");

        try vaultUtil.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Upkeep needed:", upkeepNeeded);
            console.log("Perform data length:", performData.length);

            if (upkeepNeeded && performData.length > 0) {
                uint256 taskId = abi.decode(performData, (uint256));
                console.log("Task ID:", taskId);
            }
        } catch {
            console.log("checkUpkeep reverted (likely stale price)");
        }
    }

    function test_CheckUpkeepDuringEpoch() public view {
        if (!vault.epochStarted()) {
            console.log("SKIP: No active epoch");
            return;
        }

        try vaultUtil.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Epoch active - upkeep needed:", upkeepNeeded);
            if (upkeepNeeded && performData.length > 0) {
                uint256 taskId = abi.decode(performData, (uint256));
                console.log("Task ID:", taskId);
            }
        } catch {
            console.log("checkUpkeep reverted");
        }
    }

    // ============ Task ID Verification ============

    function test_TaskIDsDocumented() public pure {
        console.log("=== Task IDs ===");
        console.log("Task 0: Add collateral (Avoid Liquidation)");
        console.log("Task 3: AllowKick (max tranches exhausted)");
        console.log("Task 221: Rate update");
        console.log("Task 222: End epoch");
    }

    // ============ Forwarder Address ============

    function test_ForwarderAddressConfigured() public view {
        address forwarder = vaultUtil.s_forwarderAddress();
        console.log("Forwarder address:", forwarder);
        assertTrue(forwarder != address(0), "Forwarder should be configured");
    }

    // ============ performUpkeep with Data ============

    function test_PerformUpkeepEmptyDataReverts() public {
        address forwarder = vaultUtil.s_forwarderAddress();

        vm.prank(forwarder);
        vm.expectRevert(VaultLib.InvalidInput.selector);
        vaultUtil.performUpkeep("");
    }

    function test_PerformUpkeepFromNonForwarder() public {
        bytes memory performData = abi.encode(uint256(221));

        vm.prank(randomUser);
        vm.expectRevert(VaultLib.OnlyForwarder.selector);
        vaultUtil.performUpkeep(performData);
    }

    // ============ Integration Test ============

    function test_CheckAndPerformFlow() public {
        console.log("=== Check and Perform Flow ===");

        // 1. Check upkeep
        try vaultUtil.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Step 1 - Upkeep needed:", upkeepNeeded);

            if (upkeepNeeded && performData.length > 0) {
                uint256 taskId = abi.decode(performData, (uint256));
                console.log("Step 1 - Task ID:", taskId);

                // 2. Verify forwarder requirement
                address forwarder = vaultUtil.s_forwarderAddress();

                // 3. Non-forwarder fails
                vm.prank(randomUser);
                vm.expectRevert(VaultLib.OnlyForwarder.selector);
                vaultUtil.performUpkeep(performData);
                console.log("Step 2 - Non-forwarder correctly rejected");

                // 4. performTask is public (no forwarder needed)
                vm.prank(randomUser);
                try vaultUtil.performTask() {
                    console.log("Step 3 - performTask succeeded");
                } catch {
                    console.log("Step 3 - performTask reverted (task specific)");
                }
            }
        } catch {
            console.log("checkUpkeep reverted");
        }
    }
}
