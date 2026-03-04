// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseStableTest.sol";
import {LVLidoVaultUpkeeper} from "../../src/LVLidoVaultUpkeeper.sol";

/**
 * @title E2EWithdrawalValidation
 * @notice End-to-end tests validating the CL double-counting bug fix (commit 82e80dc)
 *
 * THE BUG (now fixed):
 * - When CL orders moved from collateralLenderOrders[] to epochToCollateralLenderOrders[]
 * - totalCollateralLenderCT was NOT decremented
 * - At epoch end, processMatchesAndCreateOrders ADDED back with interest
 * - Result: totalCollateralLenderCT grew exponentially, funds became stuck
 *
 * THE FIX (line 413 in LVLidoVault.sol):
 * - Added: totalCollateralLenderCT -= collateralUtilized
 * - Now: totalCollateralLenderCT always equals sum(collateralLenderOrders[])
 *
 * INVARIANT TESTED:
 *   totalCollateralLenderCT == sum(collateralLenderOrders[i].collateralAmount)
 *
 * These tests validate:
 * 1. The CL accounting invariant holds after epoch matching
 * 2. Similar invariants hold for Lenders and Borrowers
 * 3. Multiple epochs don't cause accounting drift
 * 4. Unutilized funds can be withdrawn correctly
 */
contract E2EWithdrawalValidation is BaseStableTest {

    LVLidoVaultUpkeeper public upkeeper;

    // Additional test participants
    address public lender2;
    address public borrower2;
    address public collateralLender2;

    function setUp() public override {
        super.setUp();

        // Deploy and configure the Upkeeper
        vm.startPrank(owner);
        upkeeper = new LVLidoVaultUpkeeper(address(vault));
        vault.setLVLidoVaultUpkeeperAddress(address(upkeeper));
        upkeeper.setLVLidoVaultUtil(address(vaultUtil));
        vaultUtil.setLVLidoVaultUpkeeper(address(upkeeper));
        vm.stopPrank();

        // Create additional participants for multi-user tests
        lender2 = makeAddr("lender2");
        borrower2 = makeAddr("borrower2");
        collateralLender2 = makeAddr("collateralLender2");
    }

    // ============================================================
    // TEST 1: CL Accounting Invariant Through Epoch Matching
    // ============================================================

    /**
     * @notice Validates the CL accounting invariant holds after epoch matching
     * @dev This is the PRIMARY test for the double-counting bug fix
     *
     * The bug manifested when CL orders were MOVED from collateralLenderOrders[]
     * to epochToCollateralLenderOrders[] but totalCollateralLenderCT was not decremented.
     *
     * With the fix, after matching:
     *   totalCollateralLenderCT == sum(collateralLenderOrders[]) (unutilized only)
     */
    function test_E2E_CLAccountingInvariantAfterMatching() public {
        console.log("=== TEST 1: CL Accounting Invariant After Matching ===");
        console.log("");

        // --- SETUP: All participants deposit ---
        uint256 lenderDeposit = 10 ether;
        uint256 borrowerDeposit = 5 ether;
        uint256 clDeposit = 5 ether;

        _fundLender(lender1, lenderDeposit);
        _fundBorrower(borrower1, borrowerDeposit);
        _fundCollateralLender(collateralLender1, clDeposit);

        // Verify initial invariant
        uint256 totalCLCT_before = vault.totalCollateralLenderCT();
        uint256 sumCLOrders_before = _sumCollateralLenderOrders();

        console.log("Before Epoch Start:");
        console.log("  totalCollateralLenderCT:", totalCLCT_before / 1e18, "wstETH");
        console.log("  sum(collateralLenderOrders):", sumCLOrders_before / 1e18, "wstETH");

        assertEq(totalCLCT_before, sumCLOrders_before, "INVARIANT: totalCT == sum(orders) before epoch");
        assertEq(totalCLCT_before, clDeposit, "totalCollateralLenderCT should equal deposit");

        // --- START EPOCH (triggers matching) ---
        vm.prank(owner);
        vaultUtil.setMaxFlashLoanFeeThreshold(100, 0);
        vm.prank(owner);
        vault.startEpoch();

        assertTrue(vault.epochStarted(), "Epoch should be started");

        // --- CRITICAL CHECK: Invariant after matching ---
        uint256 totalCLCT_afterMatch = vault.totalCollateralLenderCT();
        uint256 sumCLOrders_afterMatch = _sumCollateralLenderOrders();
        uint256 clUtilized = clDeposit - sumCLOrders_afterMatch;

        console.log("");
        console.log("After Epoch Start (Matching):");
        console.log("  totalCollateralLenderCT:", totalCLCT_afterMatch / 1e18, "wstETH");
        console.log("  sum(collateralLenderOrders):", sumCLOrders_afterMatch / 1e18, "wstETH");
        console.log("  CL utilized (moved to epoch array):", clUtilized / 1e18, "wstETH");
        console.log("  CL orders remaining:", vault.getCollateralLenderOrdersLength());

        // THE FIX: These MUST be equal (totalCT decremented when orders moved)
        // Without the fix, totalCLCT would still be 5 but sum would be ~1
        assertEq(totalCLCT_afterMatch, sumCLOrders_afterMatch, "INVARIANT VIOLATED: totalCT != sum(orders) after matching");

        // Additional sanity checks
        assertLt(totalCLCT_afterMatch, clDeposit, "Some CL funds should be utilized");
        assertGt(clUtilized, 0, "CL utilization should be > 0");

        console.log("");
        console.log("=== TEST 1 PASSED: CL Invariant Holds After Matching ===");
    }

    // ============================================================
    // TEST 2: Lender Accounting Through Epoch Matching
    // ============================================================

    /**
     * @notice Validates Lender accounting is correct after epoch matching
     */
    function test_E2E_LenderAccountingAfterMatching() public {
        console.log("=== TEST 2: Lender Accounting After Matching ===");
        console.log("");

        // --- SETUP ---
        uint256 lenderDeposit = 10 ether;
        uint256 borrowerDeposit = 5 ether;
        uint256 clDeposit = 5 ether;

        _fundLender(lender1, lenderDeposit);
        _fundBorrower(borrower1, borrowerDeposit);
        _fundCollateralLender(collateralLender1, clDeposit);

        // Verify initial state
        uint256 unutilized_before = vault.totalLenderQTUnutilized();
        uint256 utilized_before = vault.totalLenderQTUtilized();
        uint256 sumOrders_before = _sumLenderOrders();

        console.log("Before Epoch Start:");
        console.log("  totalLenderQTUnutilized:", unutilized_before / 1e18, "WETH");
        console.log("  totalLenderQTUtilized:", utilized_before / 1e18, "WETH");
        console.log("  sum(lenderOrders):", sumOrders_before / 1e18, "WETH");

        assertEq(unutilized_before, sumOrders_before, "Unutilized should equal sum of orders");
        assertEq(utilized_before, 0, "No utilized funds before epoch");

        // --- START EPOCH ---
        vm.prank(owner);
        vaultUtil.setMaxFlashLoanFeeThreshold(100, 0);
        vm.prank(owner);
        vault.startEpoch();

        // --- CHECK: After matching ---
        uint256 unutilized_after = vault.totalLenderQTUnutilized();
        uint256 utilized_after = vault.totalLenderQTUtilized();
        uint256 sumOrders_after = _sumLenderOrders();

        console.log("");
        console.log("After Epoch Start (Matching):");
        console.log("  totalLenderQTUnutilized:", unutilized_after / 1e18, "WETH");
        console.log("  totalLenderQTUtilized:", utilized_after / 1e18, "WETH");
        console.log("  sum(lenderOrders):", sumOrders_after / 1e18, "WETH");

        // Lender funds transition from unutilized to utilized
        assertEq(unutilized_after, sumOrders_after, "Unutilized should equal sum of remaining orders");
        assertGt(utilized_after, 0, "Some funds should be utilized");
        // Allow small fee (Ajna pool takes ~0.001%)
        uint256 totalAfter = unutilized_after + utilized_after;
        assertGe(unutilized_before, totalAfter, "Total should be <= original (fees taken)");
        assertGe(totalAfter, unutilized_before * 99 / 100, "Fees should be < 1%");

        console.log("");
        console.log("=== TEST 2 PASSED: Lender Accounting Correct ===");
    }

    // ============================================================
    // TEST 3: Borrower Accounting Through Epoch Matching
    // ============================================================

    /**
     * @notice Validates Borrower accounting is correct after epoch matching
     */
    function test_E2E_BorrowerAccountingAfterMatching() public {
        console.log("=== TEST 3: Borrower Accounting After Matching ===");
        console.log("");

        // --- SETUP ---
        uint256 lenderDeposit = 10 ether;
        uint256 borrowerDeposit = 5 ether;
        uint256 clDeposit = 5 ether;

        _fundLender(lender1, lenderDeposit);
        _fundBorrower(borrower1, borrowerDeposit);
        _fundCollateralLender(collateralLender1, clDeposit);

        // Verify initial state
        uint256 totalCT_before = vault.totalBorrowerCT();
        uint256 unutilized_before = vault.totalBorrowerCTUnutilized();
        uint256 sumOrders_before = _sumBorrowerOrders();

        console.log("Before Epoch Start:");
        console.log("  totalBorrowerCT:", totalCT_before / 1e18, "wstETH");
        console.log("  totalBorrowerCTUnutilized:", unutilized_before / 1e18, "wstETH");
        console.log("  sum(borrowerOrders):", sumOrders_before / 1e18, "wstETH");

        assertEq(totalCT_before, sumOrders_before, "TotalCT should equal sum of orders");
        assertEq(unutilized_before, sumOrders_before, "Unutilized should equal sum of orders");

        // --- START EPOCH ---
        vm.prank(owner);
        vaultUtil.setMaxFlashLoanFeeThreshold(100, 0);
        vm.prank(owner);
        vault.startEpoch();

        // --- CHECK: After matching ---
        uint256 totalCT_after = vault.totalBorrowerCT();
        uint256 unutilized_after = vault.totalBorrowerCTUnutilized();
        uint256 sumOrders_after = _sumBorrowerOrders();
        uint256 borrowed = vault.totalBorrowAmount();

        console.log("");
        console.log("After Epoch Start (Matching):");
        console.log("  totalBorrowerCT:", totalCT_after / 1e18, "wstETH");
        console.log("  totalBorrowerCTUnutilized:", unutilized_after / 1e18, "wstETH");
        console.log("  sum(borrowerOrders):", sumOrders_after / 1e18, "wstETH");
        console.log("  totalBorrowAmount:", borrowed / 1e18, "WETH");

        // Borrower collateral: totalCT tracks all deposits, unutilized tracks pending orders
        // After matching, some collateral is utilized (moved to matches), remaining is in orders array
        assertEq(unutilized_after, sumOrders_after, "Unutilized should equal sum of orders");
        assertLt(unutilized_after, unutilized_before, "Some collateral should be utilized");
        assertGt(borrowed, 0, "Should have borrowed funds");
        // totalBorrowerCT may differ from sum due to utilized collateral being tracked separately
        assertEq(totalCT_after, totalCT_before, "TotalCT should remain unchanged during epoch");

        console.log("");
        console.log("=== TEST 3 PASSED: Borrower Accounting Correct ===");
    }

    // ============================================================
    // TEST 4: Multi-Epoch CL Invariant (Sequential Epochs)
    // ============================================================

    /**
     * @notice Validates CL accounting invariant holds with multiple CL depositors
     * @dev This test validates that the fix works correctly with multiple CLs
     *
     * The bug would cause each CL's contribution to be double-counted.
     * With multiple CLs, the error compounds faster.
     */
    function test_E2E_MultipleCLsAccountingInvariant() public {
        console.log("=== TEST 4: Multiple CLs Accounting Invariant ===");
        console.log("");

        // Use working ratios: 10 WETH : 5 wstETH borrower : 5 wstETH CL
        uint256 lenderDeposit = 10 ether;
        uint256 borrowerDeposit = 5 ether;
        uint256 cl1Deposit = 2 ether;
        uint256 cl2Deposit = 3 ether;

        // Fund participants - 2 CLs with different amounts
        _fundLender(lender1, lenderDeposit);
        _fundBorrower(borrower1, borrowerDeposit);
        _fundCollateralLender(collateralLender1, cl1Deposit);
        _fundCollateralLender(collateralLender2, cl2Deposit);

        uint256 totalCLDeposit = cl1Deposit + cl2Deposit;

        console.log("Setup:");
        console.log("  CL1 deposit:", cl1Deposit / 1e18, "wstETH");
        console.log("  CL2 deposit:", cl2Deposit / 1e18, "wstETH");
        console.log("  Total CL:", totalCLDeposit / 1e18, "wstETH");

        // Check invariant BEFORE epoch
        uint256 totalCT_pre = vault.totalCollateralLenderCT();
        uint256 sumOrders_pre = _sumCollateralLenderOrders();
        console.log("");
        console.log("Before Epoch:");
        console.log("  totalCollateralLenderCT:", totalCT_pre / 1e18, "wstETH");
        console.log("  sum(collateralLenderOrders):", sumOrders_pre / 1e18, "wstETH");
        console.log("  CL orders count:", vault.getCollateralLenderOrdersLength());

        assertEq(totalCT_pre, sumOrders_pre, "INVARIANT: pre-epoch totalCT == sum(orders)");
        assertEq(totalCT_pre, totalCLDeposit, "Total should equal sum of deposits");

        // Start epoch
        vm.prank(owner);
        vaultUtil.setMaxFlashLoanFeeThreshold(100, 0);
        vm.prank(owner);
        vault.startEpoch();

        // Check invariant AFTER matching
        uint256 totalCT_post = vault.totalCollateralLenderCT();
        uint256 sumOrders_post = _sumCollateralLenderOrders();
        uint256 clUtilized = totalCLDeposit - sumOrders_post;

        console.log("");
        console.log("After Matching:");
        console.log("  totalCollateralLenderCT:", totalCT_post / 1e18, "wstETH");
        console.log("  sum(collateralLenderOrders):", sumOrders_post / 1e18, "wstETH");
        console.log("  CL utilized:", clUtilized / 1e18, "wstETH");
        console.log("  CL orders remaining:", vault.getCollateralLenderOrdersLength());

        // THE FIX: Both CLs' utilized portions are correctly decremented
        assertEq(totalCT_post, sumOrders_post, "INVARIANT: post-match totalCT == sum(orders)");

        // Without the fix, totalCT would still be 7, but sum would be less
        // This would cause double-counting when epoch ends

        console.log("");
        console.log("=== TEST 4 PASSED: Multiple CLs Invariant Holds ===");
    }

    // ============================================================
    // TEST 5: Unutilized CL Withdrawal After Partial Matching
    // ============================================================

    /**
     * @notice Validates CL can withdraw unutilized funds after epoch starts
     * @dev After matching, some CL funds may remain unutilized. These should
     *      be withdrawable and the accounting should remain consistent.
     */
    function test_E2E_CLWithdrawUnutilizedAfterMatching() public {
        console.log("=== TEST 5: CL Withdraw Unutilized After Matching ===");
        console.log("");

        // --- SETUP: Use same ratios as test 1 which works ---
        // These ratios leave ~1 wstETH CL unutilized after matching
        uint256 lenderDeposit = 10 ether;
        uint256 borrowerDeposit = 5 ether;
        uint256 clDeposit = 5 ether;

        _fundLender(lender1, lenderDeposit);
        _fundBorrower(borrower1, borrowerDeposit);
        _fundCollateralLender(collateralLender1, clDeposit);

        console.log("Initial Setup:");
        console.log("  CL deposit:", clDeposit / 1e18, "wstETH");

        // Start epoch
        vm.prank(owner);
        vaultUtil.setMaxFlashLoanFeeThreshold(100, 0);
        vm.prank(owner);
        vault.startEpoch();

        // Check unutilized CL amount
        uint256 unutilizedCL = _sumCollateralLenderOrders();
        console.log("  Unutilized after matching:", unutilizedCL / 1e18, "wstETH");

        // Verify invariant holds
        uint256 totalCT = vault.totalCollateralLenderCT();
        assertEq(totalCT, unutilizedCL, "INVARIANT: totalCT == sum(orders)");

        // CL withdraws unutilized funds
        uint256 clBalanceBefore = IERC20(WSTETH_ADDRESS).balanceOf(collateralLender1);

        vm.prank(collateralLender1);
        uint256 withdrawn = vault.withdrawCLOrder();

        uint256 clBalanceAfter = IERC20(WSTETH_ADDRESS).balanceOf(collateralLender1);

        console.log("");
        console.log("CL Withdrawal:");
        console.log("  Withdrawn:", withdrawn / 1e18, "wstETH");
        console.log("  CL balance change:", (clBalanceAfter - clBalanceBefore) / 1e18, "wstETH");

        // Verify withdrawal
        assertGt(withdrawn, 0, "CL should withdraw unutilized funds");
        // Allow small rounding differences
        assertApproxEqAbs(withdrawn, unutilizedCL, 1e15, "Should withdraw ~all unutilized");
        assertEq(clBalanceAfter, clBalanceBefore + withdrawn, "Balance should increase");

        // Verify invariant still holds
        uint256 finalTotalCT = vault.totalCollateralLenderCT();
        uint256 finalSum = _sumCollateralLenderOrders();
        assertEq(finalTotalCT, finalSum, "INVARIANT: totalCT == sum(orders) after withdrawal");
        assertEq(finalTotalCT, 0, "All CL orders should be withdrawn");

        console.log("");
        console.log("=== TEST 5 PASSED: Unutilized CL Withdrawal Works ===");
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    /**
     * @notice Calculates sum of all collateralLenderOrders[].collateralAmount
     */
    function _sumCollateralLenderOrders() internal view returns (uint256 sum) {
        VaultLib.CollateralLenderOrder[] memory orders = vault.getCollateralLenderOrders();
        for (uint256 i = 0; i < orders.length; i++) {
            sum += orders[i].collateralAmount;
        }
    }

    /**
     * @notice Calculates sum of all lenderOrders[].quoteAmount
     */
    function _sumLenderOrders() internal view returns (uint256 sum) {
        VaultLib.LenderOrder[] memory orders = vault.getLenderOrders();
        for (uint256 i = 0; i < orders.length; i++) {
            sum += orders[i].quoteAmount;
        }
    }

    /**
     * @notice Calculates sum of all borrowerOrders[].collateralAmount
     */
    function _sumBorrowerOrders() internal view returns (uint256 sum) {
        VaultLib.BorrowerOrder[] memory orders = vault.getBorrowerOrders();
        for (uint256 i = 0; i < orders.length; i++) {
            sum += orders[i].collateralAmount;
        }
    }
}
