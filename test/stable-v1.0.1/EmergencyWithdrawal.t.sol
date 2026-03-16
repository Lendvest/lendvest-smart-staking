// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseStableTest.sol";

/**
 * @title EmergencyWithdrawalTest
 * @notice Tests for emergency Aave withdrawal paths (LVLidoVaultUtil)
 * @dev Validates:
 *      1. Permissionless emergency withdrawal after delay
 *      2. Per-user proportional claims
 *      3. Timing guards (too early, epoch not ended)
 *      4. Idempotency (double-withdraw returns 0)
 *      5. Invalid epoch validation
 *      6. Multi-user proportional fairness
 */
contract EmergencyWithdrawalTest is BaseStableTest {

    address internal lender2 = makeAddr("lender2");
    address internal cl2 = makeAddr("collateralLender2");
    address internal randomCaller = makeAddr("randomCaller");

    function setUp() public override {
        super.setUp();
    }

    // ============ HELPERS ============

    /// @dev Start an epoch so orders get deposited to Aave, then warp past term + delay
    function _setupEpochWithAaveDeposits() internal {
        _startBalancedEpoch();
        // Warp past term duration + emergency delay (14d + 3d + 1s)
        vm.warp(vault.epochStart() + vault.termDuration() + vault.emergencyAaveWithdrawDelay() + 1);
    }

    /// @dev Start an epoch with multiple lenders/CLs for proportional claim tests
    function _setupMultiUserEpoch() internal {
        // Fund two lenders with different amounts
        _fundLender(lender1, 10 ether);
        _fundLender(lender2, 5 ether);
        // Fund two CLs with different amounts
        _fundCollateralLender(collateralLender1, 3 ether);
        _fundCollateralLender(cl2, 2 ether);
        // Borrower
        _fundBorrower(borrower1, 5 ether);

        vm.prank(owner);
        vaultUtil.setMaxFlashLoanFeeThreshold(100, 0);

        vm.prank(owner);
        try vault.startEpoch() {
            // Epoch started successfully
        } catch (bytes memory reason) {
            bytes4 selector;
            assembly { selector := mload(add(reason, 32)) }
            if (selector == VaultLib.InsufficientFunds.selector) {
                // Skip if fork state doesn't support matching
                return;
            }
            assembly { revert(add(reason, 32), mload(reason)) }
        }

        // Warp past term + emergency delay
        vm.warp(vault.epochStart() + vault.termDuration() + vault.emergencyAaveWithdrawDelay() + 1);
    }

    // ============ VALIDATION TESTS ============

    /**
     * @notice Emergency withdraw reverts for epoch 0 (invalid)
     */
    function test_EmergencyRevertOnEpochZero() public {
        _setupEpochWithAaveDeposits();
        vm.expectRevert(VaultLib.InvalidEpoch.selector);
        vaultUtil.emergencyWithdrawLenderAaveForEpoch(0);
    }

    /**
     * @notice Emergency withdraw reverts for future epoch
     */
    function test_EmergencyRevertOnFutureEpoch() public {
        _setupEpochWithAaveDeposits();
        uint256 futureEpoch = vault.epoch() + 1;
        vm.expectRevert(VaultLib.InvalidEpoch.selector);
        vaultUtil.emergencyWithdrawLenderAaveForEpoch(futureEpoch);
    }

    /**
     * @notice Emergency withdraw reverts if called too early (before term + delay)
     */
    function test_EmergencyRevertIfTooEarly() public {
        _startBalancedEpoch();
        // Warp to just after term but BEFORE delay
        vm.warp(vault.epochStart() + vault.termDuration() + 1);

        uint256 currentEpoch = vault.epoch();
        vm.expectRevert(VaultLib.EmergencyWithdrawalTooEarly.selector);
        vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);
    }

    /**
     * @notice Emergency withdraw reverts if epoch hasn't ended (mid-term)
     */
    function test_EmergencyRevertIfEpochNotEnded() public {
        _startBalancedEpoch();
        // Still within term duration
        vm.warp(vault.epochStart() + 1 days);

        uint256 currentEpoch = vault.epoch();
        vm.expectRevert(VaultLib.EpochNotEnded.selector);
        vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);
    }

    // ============ LENDER EMERGENCY WITHDRAWAL ============

    /**
     * @notice Emergency lender Aave withdrawal succeeds after delay
     */
    function test_EmergencyWithdrawLenderAave() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 epochLenderDeposits = vault.epochToAaveLenderDeposits(currentEpoch);
        console.log("Epoch lender Aave deposits:", epochLenderDeposits);

        if (epochLenderDeposits == 0) {
            console.log("NOTE: No lender Aave deposits (all matched). Skipping.");
            return;
        }

        // Anyone can call — permissionless
        vm.prank(randomCaller);
        uint256 withdrawn = vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);

        assertGt(withdrawn, 0, "Should withdraw non-zero amount");
        assertTrue(vault.epochEmergencyLenderWithdrawn(currentEpoch), "Should mark as withdrawn");
        console.log("Emergency lender withdrawn:", withdrawn);
    }

    /**
     * @notice Double emergency withdrawal is idempotent (returns 0)
     */
    function test_EmergencyLenderIdempotent() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 epochLenderDeposits = vault.epochToAaveLenderDeposits(currentEpoch);
        if (epochLenderDeposits == 0) {
            console.log("NOTE: No lender Aave deposits. Skipping.");
            return;
        }

        // First withdrawal succeeds
        uint256 first = vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);
        assertGt(first, 0, "First should succeed");

        // Second returns 0 (idempotent)
        uint256 second = vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);
        assertEq(second, 0, "Second should return 0");
    }

    // ============ CL EMERGENCY WITHDRAWAL ============

    /**
     * @notice Emergency CL Aave withdrawal succeeds after delay
     */
    function test_EmergencyWithdrawCLAave() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 epochCLDeposits = vault.epochToAaveCLDeposits(currentEpoch);
        console.log("Epoch CL Aave deposits:", epochCLDeposits);

        if (epochCLDeposits == 0) {
            console.log("NOTE: No CL Aave deposits (all matched). Skipping.");
            return;
        }

        vm.prank(randomCaller);
        uint256 withdrawn = vaultUtil.emergencyWithdrawCLAaveForEpoch(currentEpoch);

        assertGt(withdrawn, 0, "Should withdraw non-zero amount");
        assertTrue(vault.epochEmergencyCLWithdrawn(currentEpoch), "Should mark as withdrawn");
        console.log("Emergency CL withdrawn:", withdrawn);
    }

    /**
     * @notice Double CL emergency withdrawal is idempotent
     */
    function test_EmergencyCLIdempotent() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 epochCLDeposits = vault.epochToAaveCLDeposits(currentEpoch);
        if (epochCLDeposits == 0) {
            console.log("NOTE: No CL Aave deposits. Skipping.");
            return;
        }

        uint256 first = vaultUtil.emergencyWithdrawCLAaveForEpoch(currentEpoch);
        assertGt(first, 0, "First should succeed");

        uint256 second = vaultUtil.emergencyWithdrawCLAaveForEpoch(currentEpoch);
        assertEq(second, 0, "Second should return 0");
    }

    // ============ USER CLAIM TESTS ============

    /**
     * @notice Lender can claim proportional share after emergency withdrawal
     */
    function test_EmergencyClaimLender() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 userDeposit = vault.userAaveLenderDeposits(lender1, currentEpoch);
        if (userDeposit == 0) {
            console.log("NOTE: Lender1 has no Aave deposits this epoch. Skipping.");
            return;
        }

        // First: emergency withdraw the epoch
        vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);

        uint256 lenderBalBefore = IERC20(WETH_ADDRESS).balanceOf(lender1);

        // Lender claims their share
        vm.prank(lender1);
        uint256 claimed = vaultUtil.emergencyClaimLenderAaveForEpoch(currentEpoch);

        uint256 lenderBalAfter = IERC20(WETH_ADDRESS).balanceOf(lender1);

        assertGt(claimed, 0, "Should claim non-zero");
        assertEq(lenderBalAfter - lenderBalBefore, claimed, "Balance should increase by claimed amount");

        // User deposit should be zeroed after claim
        assertEq(vault.userAaveLenderDeposits(lender1, currentEpoch), 0, "User deposit should be zeroed");

        console.log("Lender claimed:", claimed);
    }

    /**
     * @notice CL can claim proportional share after emergency withdrawal
     */
    function test_EmergencyClaimCL() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 userDeposit = vault.userAaveCLDeposits(collateralLender1, currentEpoch);
        if (userDeposit == 0) {
            console.log("NOTE: CL1 has no Aave deposits this epoch. Skipping.");
            return;
        }

        // First: emergency withdraw the epoch
        vaultUtil.emergencyWithdrawCLAaveForEpoch(currentEpoch);

        uint256 clBalBefore = IERC20(WSTETH_ADDRESS).balanceOf(collateralLender1);

        // CL claims their share
        vm.prank(collateralLender1);
        uint256 claimed = vaultUtil.emergencyClaimCLAaveForEpoch(currentEpoch);

        uint256 clBalAfter = IERC20(WSTETH_ADDRESS).balanceOf(collateralLender1);

        assertGt(claimed, 0, "Should claim non-zero");
        assertEq(clBalAfter - clBalBefore, claimed, "Balance should increase by claimed amount");
        assertEq(vault.userAaveCLDeposits(collateralLender1, currentEpoch), 0, "User deposit should be zeroed");

        console.log("CL claimed:", claimed);
    }

    /**
     * @notice Claim reverts if user has no deposit
     */
    function test_EmergencyClaimRevertsNoDeposit() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 epochLenderDeposits = vault.epochToAaveLenderDeposits(currentEpoch);
        if (epochLenderDeposits == 0) {
            console.log("NOTE: No Aave deposits. Skipping.");
            return;
        }

        vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);

        // Random address with no deposits tries to claim
        vm.prank(randomCaller);
        vm.expectRevert(VaultLib.NoEmergencyClaim.selector);
        vaultUtil.emergencyClaimLenderAaveForEpoch(currentEpoch);
    }

    /**
     * @notice Claim reverts if emergency withdraw hasn't happened yet
     */
    function test_EmergencyClaimRevertsBeforeWithdraw() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 userDeposit = vault.userAaveLenderDeposits(lender1, currentEpoch);
        if (userDeposit == 0) {
            console.log("NOTE: Lender1 has no Aave deposits. Skipping.");
            return;
        }

        // Try to claim without calling emergencyWithdrawLenderAaveForEpoch first
        vm.prank(lender1);
        vm.expectRevert(VaultLib.NoEmergencyClaim.selector);
        vaultUtil.emergencyClaimLenderAaveForEpoch(currentEpoch);
    }

    /**
     * @notice Double claim reverts (user principal zeroed after first claim)
     */
    function test_EmergencyDoubleClaimReverts() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 userDeposit = vault.userAaveLenderDeposits(lender1, currentEpoch);
        if (userDeposit == 0) {
            console.log("NOTE: No deposit. Skipping.");
            return;
        }

        vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);

        // First claim succeeds
        vm.prank(lender1);
        vaultUtil.emergencyClaimLenderAaveForEpoch(currentEpoch);

        // Second claim reverts
        vm.prank(lender1);
        vm.expectRevert(VaultLib.NoEmergencyClaim.selector);
        vaultUtil.emergencyClaimLenderAaveForEpoch(currentEpoch);
    }

    // ============ MULTI-USER PROPORTIONAL TESTS ============

    /**
     * @notice Multiple lenders get proportional shares of emergency withdrawal
     */
    function test_EmergencyMultiLenderProportionalClaims() public {
        _setupMultiUserEpoch();
        uint256 currentEpoch = vault.epoch();

        uint256 l1Deposit = vault.userAaveLenderDeposits(lender1, currentEpoch);
        uint256 l2Deposit = vault.userAaveLenderDeposits(lender2, currentEpoch);

        if (l1Deposit == 0 && l2Deposit == 0) {
            console.log("NOTE: No lender Aave deposits. Skipping.");
            return;
        }

        console.log("Lender1 Aave deposit:", l1Deposit);
        console.log("Lender2 Aave deposit:", l2Deposit);

        // Emergency withdraw
        vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);

        // Both claim
        uint256 l1Claimed;
        uint256 l2Claimed;

        if (l1Deposit > 0) {
            vm.prank(lender1);
            l1Claimed = vaultUtil.emergencyClaimLenderAaveForEpoch(currentEpoch);
        }
        if (l2Deposit > 0) {
            vm.prank(lender2);
            l2Claimed = vaultUtil.emergencyClaimLenderAaveForEpoch(currentEpoch);
        }

        console.log("Lender1 claimed:", l1Claimed);
        console.log("Lender2 claimed:", l2Claimed);

        // Verify proportionality: if l1 deposited 2x l2, they should get ~2x the claim
        if (l1Deposit > 0 && l2Deposit > 0) {
            // Allow 1% tolerance for rounding
            uint256 ratio = (l1Claimed * 100) / l2Claimed;
            uint256 expectedRatio = (l1Deposit * 100) / l2Deposit;
            assertApproxEqRel(ratio, expectedRatio, 0.01e18, "Claims should be proportional to deposits");
        }
    }

    /**
     * @notice Multiple CLs get proportional shares of emergency withdrawal
     */
    function test_EmergencyMultiCLProportionalClaims() public {
        _setupMultiUserEpoch();
        uint256 currentEpoch = vault.epoch();

        uint256 cl1Deposit = vault.userAaveCLDeposits(collateralLender1, currentEpoch);
        uint256 cl2Deposit = vault.userAaveCLDeposits(cl2, currentEpoch);

        if (cl1Deposit == 0 && cl2Deposit == 0) {
            console.log("NOTE: No CL Aave deposits. Skipping.");
            return;
        }

        console.log("CL1 Aave deposit:", cl1Deposit);
        console.log("CL2 Aave deposit:", cl2Deposit);

        // Emergency withdraw
        vaultUtil.emergencyWithdrawCLAaveForEpoch(currentEpoch);

        uint256 cl1Claimed;
        uint256 cl2Claimed;

        if (cl1Deposit > 0) {
            vm.prank(collateralLender1);
            cl1Claimed = vaultUtil.emergencyClaimCLAaveForEpoch(currentEpoch);
        }
        if (cl2Deposit > 0) {
            vm.prank(cl2);
            cl2Claimed = vaultUtil.emergencyClaimCLAaveForEpoch(currentEpoch);
        }

        console.log("CL1 claimed:", cl1Claimed);
        console.log("CL2 claimed:", cl2Claimed);

        if (cl1Deposit > 0 && cl2Deposit > 0) {
            uint256 ratio = (cl1Claimed * 100) / cl2Claimed;
            uint256 expectedRatio = (cl1Deposit * 100) / cl2Deposit;
            assertApproxEqRel(ratio, expectedRatio, 0.01e18, "Claims should be proportional to deposits");
        }
    }

    // ============ PERMISSIONLESS ACCESS ============

    /**
     * @notice Any address can trigger emergency withdrawal (permissionless)
     */
    function test_EmergencyIsPermissionless() public {
        _setupEpochWithAaveDeposits();
        uint256 currentEpoch = vault.epoch();

        uint256 epochDeposits = vault.epochToAaveLenderDeposits(currentEpoch);
        if (epochDeposits == 0) {
            console.log("NOTE: No deposits. Skipping.");
            return;
        }

        // Random address triggers emergency withdrawal
        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        uint256 withdrawn = vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);
        assertGt(withdrawn, 0, "Anyone should be able to trigger emergency withdrawal");
    }
}
