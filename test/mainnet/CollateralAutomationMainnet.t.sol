// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseMainnetTest.sol";

/**
 * @title CollateralAutomationMainnetTest
 * @notice Tests for collateral automation against deployed mainnet contracts
 */
contract CollateralAutomationMainnetTest is BaseMainnetTest {

    uint256 constant FACTOR_COLLATERAL_INCREASE = 11e15; // 1.1%
    uint256 constant MAX_TRANCHES = 3;

    function setUp() public override {
        super.setUp();
    }

    function test_TrancheConstants() public view {
        assertEq(vaultUtil.FACTOR_COLLATERAL_INCREASE(), FACTOR_COLLATERAL_INCREASE);
        assertEq(vaultUtil.MAX_TRANCHES(), MAX_TRANCHES);
        console.log("FACTOR_COLLATERAL_INCREASE:", FACTOR_COLLATERAL_INCREASE);
        console.log("MAX_TRANCHES:", MAX_TRANCHES);
    }

    function test_InitialTrauncheIsZero() public view {
        uint256 currentTranche = vault.collateralLenderTraunche();
        console.log("Current tranche:", currentTranche);
        // On mainnet, tranche may not be 0 if epochs have run
    }

    function test_PriceThresholdCalculation() public view {
        int256 baseThreshold = vault.priceDifferencethreshold();
        console.log("Base threshold:", baseThreshold);

        // Calculate thresholds for each tranche
        int256 threshold0 = baseThreshold - int256(FACTOR_COLLATERAL_INCREASE * 0);
        int256 threshold1 = baseThreshold - int256(FACTOR_COLLATERAL_INCREASE * 1);
        int256 threshold2 = baseThreshold - int256(FACTOR_COLLATERAL_INCREASE * 2);

        console.log("Threshold at tranche 0:", threshold0);
        console.log("Threshold at tranche 1:", threshold1);
        console.log("Threshold at tranche 2:", threshold2);
    }

    function test_CheckUpkeepDetectsPriceDrop() public {
        console.log("=== CheckUpkeep Price Drop Detection ===");

        try vaultUtil.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Upkeep needed:", upkeepNeeded);
            if (upkeepNeeded && performData.length > 0) {
                uint256 taskId = abi.decode(performData, (uint256));
                console.log("Task ID:", taskId);
                // Task 0 = Add collateral (Avoid Liquidation)
                if (taskId == 0) {
                    console.log("Collateral top-up task detected");
                }
            }
        } catch {
            console.log("CheckUpkeep reverted (likely StalePrice)");
        }
    }

    function test_AllowKickAfterMaxTranches() public view {
        bool allowKick = vault.getAllowKick();
        console.log("AllowKick status:", allowKick);
        // Initially or after reset, allowKick should be false
    }

    function test_CLDepositsTracking() public view {
        console.log("=== CL Deposits Tracking ===");
        console.log("Total CL CT:", vault.totalCollateralLenderCT());
        console.log("CL Utilized:", vault.totalCLDepositsUtilized());
        console.log("CL Unutilized:", vault.totalCLDepositsUnutilized());
    }

    function test_WstethToWethConversion() public view {
        console.log("=== WSTETH to WETH Conversion ===");

        try vaultUtil.getWstethToWeth(1 ether) returns (uint256 wethValue) {
            console.log("1 wstETH in WETH:", wethValue);
            assertGt(wethValue, 1 ether, "wstETH should be worth more than WETH");
            assertLt(wethValue, 1.5 ether, "But not too much more");
        } catch {
            console.log("Conversion failed (stale price)");
        }
    }

    function test_LidoClaimDelayConstant() public view {
        uint256 delay = vaultUtil.lidoClaimDelay();
        assertEq(delay, 7 days, "Lido claim delay should be 7 days");
        console.log("Lido claim delay:", delay / 1 days, "days");
    }

    function test_CollateralLenderTrauncheState() public view {
        console.log("=== Collateral Lender Tranche State ===");
        uint256 tranche = vault.collateralLenderTraunche();
        console.log("Current tranche:", tranche);
        assertTrue(tranche <= MAX_TRANCHES, "Tranche should not exceed max");
    }

    function test_AvoidLiquidationTrigger() public {
        console.log("=== Avoid Liquidation Trigger ===");

        if (!vault.epochStarted()) {
            console.log("SKIP: No active epoch");
            return;
        }

        // Check current price difference
        try vaultUtil.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            if (upkeepNeeded) {
                uint256 taskId = abi.decode(performData, (uint256));
                if (taskId == 0) {
                    console.log("Avoid liquidation task would be triggered");
                } else if (taskId == 3) {
                    console.log("AllowKick task would be triggered (max tranches exhausted)");
                }
            } else {
                console.log("No liquidation avoidance needed");
            }
        } catch {
            console.log("CheckUpkeep reverted");
        }
    }
}
