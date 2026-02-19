// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseStableTest.sol";

/**
 * @title AutomationsIntegrationTest
 * @notice Tests for Functions→Automations migration (commit e5661c2)
 * @dev Validates:
 *      1. LVLidoVaultUtil holds Chainlink Functions logic
 *      2. Vault delegates to Util for automation
 *      3. Forwarder address management
 *      4. Subscription and request configuration
 */
contract AutomationsIntegrationTest is BaseStableTest {

    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test vault references util correctly
     */
    function test_VaultReferencesUtil() public view {
        assertEq(
            vault.LVLidoVaultUtil(),
            address(vaultUtil),
            "Vault should reference util"
        );
    }

    /**
     * @notice Test util references vault correctly
     */
    function test_UtilReferencesVault() public view {
        assertEq(
            address(vaultUtil.LVLidoVault()),
            address(vault),
            "Util should reference vault"
        );
    }

    /**
     * @notice Test forwarder address management
     */
    function test_ForwarderAddressManagement() public {
        assertEq(vaultUtil.s_forwarderAddress(), forwarder, "Initial forwarder set");

        // Change forwarder
        address newForwarder = makeAddr("newForwarder");
        vm.prank(owner);
        vaultUtil.setForwarderAddress(newForwarder);

        assertEq(vaultUtil.s_forwarderAddress(), newForwarder, "Forwarder updated");
    }

    /**
     * @notice Test only owner can set forwarder
     */
    function test_OnlyOwnerCanSetForwarder() public {
        address newForwarder = makeAddr("newForwarder");

        vm.prank(lender1);
        vm.expectRevert("Only callable by LVLidoVault");
        vaultUtil.setForwarderAddress(newForwarder);
    }

    /**
     * @notice Test zero address rejected for forwarder
     */
    function test_ZeroAddressRejectedForForwarder() public {
        vm.prank(owner);
        vm.expectRevert(VaultLib.InvalidInput.selector);
        vaultUtil.setForwarderAddress(address(0));
    }

    /**
     * @notice Test setRequest configuration
     */
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

    /**
     * @notice Test only owner can set request
     */
    function test_OnlyOwnerCanSetRequest() public {
        vm.prank(lender1);
        vm.expectRevert("Only callable by LVLidoVault");
        vaultUtil.setRequest(hex"1234", 123, 300000);
    }

    /**
     * @notice Test checkUpkeep interface compliance
     * @dev Must start epoch first to avoid division by zero in currentRedemptionRate calculation
     */
    function test_CheckUpkeepInterface() public {
        // Start balanced epoch first to avoid division by zero
        _startBalancedEpoch();

        (bool upkeepNeeded, bytes memory performData) = vaultUtil.checkUpkeep("");

        // Should return without error
        console.log("Upkeep needed:", upkeepNeeded);
        console.log("Perform data length:", performData.length);
    }

    /**
     * @notice Test performUpkeep requires forwarder
     */
    function test_PerformUpkeepRequiresForwarder() public {
        bytes memory performData = abi.encode(uint256(0));

        vm.prank(lender1);
        vm.expectRevert(VaultLib.OnlyForwarder.selector);
        vaultUtil.performUpkeep(performData);
    }

    /**
     * @notice Test performUpkeep with empty data reverts
     */
    function test_PerformUpkeepEmptyDataReverts() public {
        vm.prank(forwarder);
        vm.expectRevert(VaultLib.InvalidInput.selector);
        vaultUtil.performUpkeep("");
    }

    /**
     * @notice Test state variables initialized correctly
     */
    function test_StateVariablesInitialized() public view {
        assertTrue(vaultUtil.updateRateNeeded(), "updateRateNeeded should be true initially");
        assertEq(vaultUtil.s_requestCounter(), 0, "Request counter should be 0");
    }

    /**
     * @notice Test price feed addresses are set
     */
    function test_PriceFeedAddresses() public view {
        // These are set in constructor and used by getWstethToWeth
        uint256 conversion = vaultUtil.getWstethToWeth(1 ether);
        assertGt(conversion, 0, "Price feeds should work");
    }
}
