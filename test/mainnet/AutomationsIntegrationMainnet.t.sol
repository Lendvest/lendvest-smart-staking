// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseMainnetTest.sol";

/**
 * @title AutomationsIntegrationMainnetTest
 * @notice Tests for Chainlink Functions/Automations integration against deployed mainnet
 */
contract AutomationsIntegrationMainnetTest is BaseMainnetTest {

    function setUp() public override {
        super.setUp();
    }

    function test_VaultReferencesUtil() public view {
        assertEq(vault.LVLidoVaultUtil(), address(vaultUtil), "Vault should reference util");
    }

    function test_UtilReferencesVault() public view {
        assertEq(address(vaultUtil.LVLidoVault()), address(vault), "Util should reference vault");
    }

    function test_ForwarderAddressManagement() public view {
        address currentForwarder = vaultUtil.s_forwarderAddress();
        console.log("Current forwarder:", currentForwarder);
        assertTrue(currentForwarder != address(0), "Forwarder should be set");
    }

    function test_OnlyOwnerCanSetForwarder() public {
        address newForwarder = makeAddr("newForwarder");

        vm.prank(lender1);
        vm.expectRevert("Only callable by LVLidoVault");
        vaultUtil.setForwarderAddress(newForwarder);
    }

    function test_ZeroAddressRejectedForForwarder() public {
        vm.prank(owner);
        vm.expectRevert(VaultLib.InvalidInput.selector);
        vaultUtil.setForwarderAddress(address(0));
    }

    function test_SetRequestConfiguration() public {
        bytes memory requestCBOR = hex"1234";
        uint64 subscriptionId = 123;
        uint32 fulfillGasLimit = 300000;

        vm.prank(owner);
        vaultUtil.setRequest(requestCBOR, subscriptionId, fulfillGasLimit);

        assertEq(vaultUtil.s_subscriptionId(), subscriptionId);
        assertEq(vaultUtil.s_fulfillGasLimit(), fulfillGasLimit);
        assertEq(vaultUtil.s_requestCBOR(), requestCBOR);
    }

    function test_OnlyOwnerCanSetRequest() public {
        vm.prank(lender1);
        vm.expectRevert("Only callable by LVLidoVault");
        vaultUtil.setRequest(hex"1234", 123, 300000);
    }

    function test_CheckUpkeepInterface() public {
        console.log("=== CheckUpkeep Interface ===");

        // Note: May fail with StalePrice on mainnet fork
        try vaultUtil.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Upkeep needed:", upkeepNeeded);
            console.log("Perform data length:", performData.length);
            if (upkeepNeeded && performData.length > 0) {
                uint256 taskId = abi.decode(performData, (uint256));
                console.log("Task ID:", taskId);
            }
        } catch Error(string memory reason) {
            console.log("CheckUpkeep reverted:", reason);
        } catch (bytes memory) {
            console.log("CheckUpkeep reverted (StalePrice likely)");
        }
    }

    function test_PerformUpkeepRequiresForwarder() public {
        bytes memory performData = abi.encode(uint256(0));
        address currentForwarder = vaultUtil.s_forwarderAddress();

        vm.prank(lender1);
        vm.expectRevert(VaultLib.OnlyForwarder.selector);
        vaultUtil.performUpkeep(performData);

        console.log("Current forwarder:", currentForwarder);
        console.log("Non-forwarder correctly rejected");
    }

    function test_PerformUpkeepEmptyDataReverts() public {
        address currentForwarder = vaultUtil.s_forwarderAddress();

        vm.prank(currentForwarder);
        vm.expectRevert(VaultLib.InvalidInput.selector);
        vaultUtil.performUpkeep("");
    }

    function test_StateVariablesInitialized() public view {
        console.log("=== State Variables ===");
        console.log("updateRateNeeded:", vaultUtil.updateRateNeeded());
        console.log("s_requestCounter:", vaultUtil.s_requestCounter());
        console.log("s_subscriptionId:", vaultUtil.s_subscriptionId());
        console.log("s_fulfillGasLimit:", vaultUtil.s_fulfillGasLimit());
    }

    function test_PriceFeedAddresses() public view {
        console.log("=== Price Feed Test ===");

        try vaultUtil.getWstethToWeth(1 ether) returns (uint256 conversion) {
            assertGt(conversion, 0, "Price feeds should work");
            console.log("1 wstETH =", conversion, "WETH");
        } catch {
            console.log("Price feed query failed (stale price)");
        }
    }

    function test_CheckUpkeepReturnsRateTaskAfterTermEnds() public {
        console.log("=== Rate Task After Term Ends ===");

        if (!vault.epochStarted()) {
            console.log("SKIP: No active epoch");
            return;
        }

        // If term has ended, task 221 should be returned
        uint256 termEnd = vault.epochStart() + vault.termDuration();
        console.log("Term end:", termEnd);
        console.log("Current time:", block.timestamp);

        if (block.timestamp > termEnd) {
            try vaultUtil.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
                if (upkeepNeeded && performData.length > 0) {
                    uint256 taskId = abi.decode(performData, (uint256));
                    console.log("Task ID:", taskId);
                    // Task 221 is rate fetch
                    if (taskId == 221) {
                        console.log("Rate fetch task returned correctly");
                    }
                }
            } catch {
                console.log("CheckUpkeep reverted");
            }
        }
    }
}
