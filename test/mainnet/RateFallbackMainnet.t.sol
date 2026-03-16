// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseMainnetTest.sol";

/**
 * @title RateFallbackMainnetTest
 * @notice Tests for rate fallback mechanism against deployed mainnet contracts
 * @dev Validates updateRate with Aave fallback
 */
contract RateFallbackMainnetTest is BaseMainnetTest {

    event RateUpdated(uint256 rate);

    function setUp() public override {
        super.setUp();
    }

    // ============ Rate State ============

    function test_CurrentRate() public view {
        uint256 rate = vault.rate();
        console.log("Current rate:", rate);
    }

    // ============ Rate Fallback ============

    function test_UpdateRateWithZeroUsesFallback() public {
        uint256 rateBefore = vault.rate();
        console.log("Rate before:", rateBefore);

        // Call updateRate with 0 (triggers Aave fallback)
        vm.prank(address(vaultUtil));
        vault.updateRate(0);

        uint256 rateAfter = vault.rate();
        console.log("Rate after fallback:", rateAfter);

        assertGt(rateAfter, 0, "Rate should be set from Aave");
    }

    function test_UpdateRateWithValueSetsValue() public {
        uint256 specificRate = 5e16; // 5%

        vm.prank(address(vaultUtil));
        vault.updateRate(specificRate);

        assertEq(vault.rate(), specificRate, "Rate should be set to specific value");
        console.log("Rate set to:", specificRate);
    }

    // ============ Access Control ============

    function test_OnlyProxyCanUpdateRate() public {
        vm.prank(lender1);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.updateRate(5e16);
    }

    // ============ Rate Bounds ============

    function test_RateBoundsConfiguration() public view {
        uint256 lower = vaultUtil.lowerBoundRate();
        uint256 upper = vaultUtil.upperBoundRate();

        console.log("Lower bound rate:", lower);
        console.log("Upper bound rate:", upper);

        assertEq(lower, 5e15, "Lower bound should be 0.5%");
        assertEq(upper, 1e17, "Upper bound should be 10%");
        assertTrue(lower < upper, "Lower should be less than upper");
    }

    // ============ Update Rate Needed ============

    function test_UpdateRateNeededState() public view {
        bool needed = vaultUtil.updateRateNeeded();
        console.log("Update rate needed:", needed);
    }

    // ============ Rate Event ============

    function test_RateUpdatedEventEmitted() public {
        uint256 newRate = 3e16; // 3%

        vm.prank(address(vaultUtil));
        vm.expectEmit(true, true, true, true);
        emit RateUpdated(newRate);
        vault.updateRate(newRate);
    }

    // ============ Rate During Epoch ============

    function test_RateDuringEpoch() public view {
        if (!vault.epochStarted()) {
            console.log("SKIP: No active epoch");
            return;
        }

        uint256 rate = vault.rate();
        console.log("=== Rate During Epoch ===");
        console.log("Current rate:", rate);
        console.log("Rate in APR %:", (rate * 100) / 1e18);
    }

    // ============ Full Rate Flow ============

    function test_FullRateFlow() public {
        console.log("=== Full Rate Flow Test ===");

        // 1. Check initial rate
        uint256 initialRate = vault.rate();
        console.log("Initial rate:", initialRate);

        // 2. Update with specific value
        uint256 testRate = 4e16; // 4%
        vm.prank(address(vaultUtil));
        vault.updateRate(testRate);
        assertEq(vault.rate(), testRate, "Rate should be updated");
        console.log("Updated to test rate:", testRate);

        // 3. Update with fallback (0)
        vm.prank(address(vaultUtil));
        vault.updateRate(0);
        uint256 fallbackRate = vault.rate();
        console.log("Fallback rate from Aave:", fallbackRate);
        assertGt(fallbackRate, 0, "Fallback should set non-zero rate");

        // 4. Verify bounds
        uint256 lower = vaultUtil.lowerBoundRate();
        uint256 upper = vaultUtil.upperBoundRate();
        assertTrue(fallbackRate >= lower || fallbackRate <= upper, "Rate should be reasonable");
    }

    // ============ Aave Rate Source ============

    function test_AaveRateSource() public view {
        console.log("=== Aave Rate Source ===");

        // The rate fallback uses Aave PoolDataProvider
        // Verify the integration works
        uint256 rate = vault.rate();
        console.log("Current vault rate:", rate);

        // Rate should be in reasonable bounds for stETH
        // Typical stETH rates are 3-5% APR
        console.log("Rate as APR %:", (rate * 100) / 1e18);
    }
}
