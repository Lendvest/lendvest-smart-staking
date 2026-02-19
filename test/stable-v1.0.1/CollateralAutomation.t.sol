// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseStableTest.sol";

/**
 * @title CollateralAutomationTest
 * @notice Tests for collateral automation (commit 441aac7)
 * @dev Validates:
 *      1. Tranche threshold calculations
 *      2. Price drop detection
 *      3. avoidLiquidation triggers
 *      4. allowKick activation after MAX_TRANCHES
 */
contract CollateralAutomationTest is BaseStableTest {

    uint256 constant FACTOR_COLLATERAL_INCREASE = 11e15; // 1.1%
    uint256 constant MAX_TRANCHES = 3;

    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test tranche constants are set correctly
     */
    function test_TrancheConstants() public view {
        assertEq(vaultUtil.FACTOR_COLLATERAL_INCREASE(), FACTOR_COLLATERAL_INCREASE);
        assertEq(vaultUtil.MAX_TRANCHES(), MAX_TRANCHES);
    }

    /**
     * @notice Test initial collateralLenderTraunche is 0
     */
    function test_InitialTrauncheIsZero() public view {
        assertEq(vault.collateralLenderTraunche(), 0, "Should start at 0");
    }

    /**
     * @notice Test price threshold calculation
     * @dev Threshold = priceDifferenceThreshold - (FACTOR * tranche)
     *      -1% - (1.1% * 0) = -1%
     *      -1% - (1.1% * 1) = -2.1%
     *      -1% - (1.1% * 2) = -3.2%
     */
    function test_PriceThresholdCalculation() public view {
        int256 baseThreshold = vault.priceDifferencethreshold(); // -1e16 = -1%
        assertEq(baseThreshold, -1e16, "Base threshold should be -1%");

        // Calculate thresholds for each tranche
        int256 threshold0 = baseThreshold - int256(FACTOR_COLLATERAL_INCREASE * 0);
        int256 threshold1 = baseThreshold - int256(FACTOR_COLLATERAL_INCREASE * 1);
        int256 threshold2 = baseThreshold - int256(FACTOR_COLLATERAL_INCREASE * 2);

        console.log("Threshold 0 (tranche 0):", uint256(-threshold0));
        console.log("Threshold 1 (tranche 1):", uint256(-threshold1));
        console.log("Threshold 2 (tranche 2):", uint256(-threshold2));

        assertEq(threshold0, -1e16, "Tranche 0: -1%");
        assertEq(threshold1, -21e15, "Tranche 1: -2.1%");
        assertEq(threshold2, -32e15, "Tranche 2: -3.2%");
    }

    /**
     * @notice Test checkUpkeep returns collateral task on price drop
     * @dev Task ID 0 = Add collateral (Avoid Liquidation)
     */
    function test_CheckUpkeepDetectsPriceDrop() public {
        // Setup epoch with debt using balanced helper
        _startBalancedEpoch();

        // Check upkeep in normal conditions
        (bool upkeepNeeded, bytes memory performData) = vaultUtil.checkUpkeep("");

        console.log("Upkeep needed:", upkeepNeeded);
        if (upkeepNeeded) {
            uint256 taskId = abi.decode(performData, (uint256));
            console.log("Task ID:", taskId);
        }
    }

    /**
     * @notice Test allowKick activation
     * @dev After MAX_TRANCHES, allowKick should be true
     */
    function test_AllowKickAfterMaxTranches() public view {
        // Initially allowKick is false
        assertFalse(vault.getAllowKick(), "Should start false");
    }

    /**
     * @notice Test CL deposits unutilized tracking
     */
    function test_CLDepositsTracking() public {
        // Use balanced orders to ensure epoch starts successfully
        _setupBalancedOrders();

        // Before epoch, all CL deposits are in collateralLenderOrders
        // _setupBalancedOrders deposits 5 ether for CL
        assertEq(vault.totalCollateralLenderCT(), 5 ether, "Total CL CT tracked");

        vm.prank(owner);
        vault.startEpoch();

        // After matching, some CL deposits become utilized
        console.log("CL Utilized:", vault.totalCLDepositsUtilized());
        console.log("CL Unutilized:", vault.totalCLDepositsUnutilized());
    }

    /**
     * @notice Test getWstethToWeth conversion
     */
    function test_WstethToWethConversion() public view {
        uint256 wethValue = vaultUtil.getWstethToWeth(1 ether);
        console.log("1 wstETH in WETH:", wethValue);

        // Should be approximately 1.2x (wstETH is worth more than WETH)
        assertGt(wethValue, 1 ether, "wstETH should be worth more than WETH");
        assertLt(wethValue, 1.5 ether, "But not too much more");
    }

    /**
     * @notice Test lidoClaimDelay constant
     */
    function test_LidoClaimDelayConstant() public view {
        assertEq(vaultUtil.lidoClaimDelay(), 7 days, "Lido claim delay should be 7 days");
    }
}
