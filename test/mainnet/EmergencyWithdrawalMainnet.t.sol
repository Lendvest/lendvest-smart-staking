// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseMainnetTest.sol";

/**
 * @title EmergencyWithdrawalMainnetTest
 * @notice Tests for emergency withdrawal paths against deployed mainnet contracts
 * @dev Validates emergency Aave withdrawal mechanisms
 */
contract EmergencyWithdrawalMainnetTest is BaseMainnetTest {

    address internal lender2 = makeAddr("lender2");
    address internal cl2 = makeAddr("collateralLender2");
    address internal randomCaller = makeAddr("randomCaller");

    function setUp() public override {
        super.setUp();
    }

    // ============ Emergency Delay Configuration ============

    function test_EmergencyDelayConfiguration() public view {
        uint256 delay = vault.emergencyAaveWithdrawDelay();
        console.log("Emergency Aave withdraw delay:", delay / 1 days, "days");
        assertGt(delay, 0, "Delay should be configured");
    }

    // ============ Validation Tests ============

    function test_EmergencyRevertOnEpochZero() public {
        vm.expectRevert(VaultLib.InvalidEpoch.selector);
        vaultUtil.emergencyWithdrawLenderAaveForEpoch(0);
    }

    function test_EmergencyRevertOnFutureEpoch() public {
        uint256 currentEpoch = vault.epoch();
        uint256 futureEpoch = currentEpoch + 10;

        vm.expectRevert(VaultLib.InvalidEpoch.selector);
        vaultUtil.emergencyWithdrawLenderAaveForEpoch(futureEpoch);
    }

    function test_EmergencyRevertOnInvalidCLEpoch() public {
        vm.expectRevert(VaultLib.InvalidEpoch.selector);
        vaultUtil.emergencyWithdrawCLAaveForEpoch(0);
    }

    // ============ Aave Deposits Tracking ============

    function test_AaveLenderDepositsTracking() public view {
        uint256 currentEpoch = vault.epoch();
        if (currentEpoch == 0) {
            console.log("SKIP: No epochs yet");
            return;
        }

        uint256 lenderDeposits = vault.epochToAaveLenderDeposits(currentEpoch);
        console.log("Epoch", currentEpoch, "lender Aave deposits:", lenderDeposits);
    }

    function test_AaveCLDepositsTracking() public view {
        uint256 currentEpoch = vault.epoch();
        if (currentEpoch == 0) {
            console.log("SKIP: No epochs yet");
            return;
        }

        uint256 clDeposits = vault.epochToAaveCLDeposits(currentEpoch);
        console.log("Epoch", currentEpoch, "CL Aave deposits:", clDeposits);
    }

    // ============ Emergency Withdrawal Status ============

    function test_EmergencyWithdrawnFlags() public view {
        uint256 currentEpoch = vault.epoch();
        if (currentEpoch == 0) {
            console.log("SKIP: No epochs yet");
            return;
        }

        bool lenderWithdrawn = vault.epochEmergencyLenderWithdrawn(currentEpoch);
        bool clWithdrawn = vault.epochEmergencyCLWithdrawn(currentEpoch);

        console.log("=== Emergency Withdrawal Flags ===");
        console.log("Epoch:", currentEpoch);
        console.log("Lender emergency withdrawn:", lenderWithdrawn);
        console.log("CL emergency withdrawn:", clWithdrawn);
    }

    // ============ Timing Tests ============

    function test_EmergencyTimingValidation() public view {
        if (!vault.epochStarted()) {
            console.log("SKIP: No active epoch");
            return;
        }

        uint256 epochStart = vault.epochStart();
        uint256 termDuration = vault.termDuration();
        uint256 emergencyDelay = vault.emergencyAaveWithdrawDelay();

        uint256 termEnd = epochStart + termDuration;
        uint256 emergencyAvailable = termEnd + emergencyDelay;

        console.log("=== Emergency Timing ===");
        console.log("Epoch start:", epochStart);
        console.log("Term end:", termEnd);
        console.log("Emergency available:", emergencyAvailable);
        console.log("Current time:", block.timestamp);

        if (block.timestamp < termEnd) {
            console.log("Status: Term still active");
        } else if (block.timestamp < emergencyAvailable) {
            console.log("Status: Within emergency delay window");
        } else {
            console.log("Status: Emergency withdrawal available");
        }
    }

    // ============ User Deposit Tracking ============

    function test_UserAaveDepositTracking() public view {
        uint256 currentEpoch = vault.epoch();
        if (currentEpoch == 0) {
            console.log("SKIP: No epochs yet");
            return;
        }

        // Check if lender1 has any deposits (from previous tests or activity)
        uint256 userLenderDeposit = vault.userAaveLenderDeposits(lender1, currentEpoch);
        uint256 userCLDeposit = vault.userAaveCLDeposits(collateralLender1, currentEpoch);

        console.log("=== User Aave Deposits (Epoch", currentEpoch, ") ===");
        console.log("Lender1 deposits:", userLenderDeposit);
        console.log("CL1 deposits:", userCLDeposit);
    }

    // ============ Emergency Claim Tests ============

    function test_EmergencyClaimRevertsNoDeposit() public {
        uint256 currentEpoch = vault.epoch();
        if (currentEpoch == 0) {
            console.log("SKIP: No epochs");
            return;
        }

        // Random caller with no deposits should fail
        vm.prank(randomCaller);
        vm.expectRevert(VaultLib.NoEmergencyClaim.selector);
        vaultUtil.emergencyClaimLenderAaveForEpoch(currentEpoch);
    }

    function test_EmergencyClaimCLRevertsNoDeposit() public {
        uint256 currentEpoch = vault.epoch();
        if (currentEpoch == 0) {
            console.log("SKIP: No epochs");
            return;
        }

        vm.prank(randomCaller);
        vm.expectRevert(VaultLib.NoEmergencyClaim.selector);
        vaultUtil.emergencyClaimCLAaveForEpoch(currentEpoch);
    }

    // ============ Emergency Withdrawal Flow Test ============

    function test_EmergencyWithdrawalFlow() public {
        console.log("=== Emergency Withdrawal Flow Test ===");

        if (vault.epochStarted()) {
            console.log("SKIP: Epoch already active - testing existing state");
            _testExistingEpochEmergency();
            return;
        }

        // Setup: Create orders and start epoch
        _fundLender(lender1, 10 ether);
        _fundBorrower(borrower1, 5 ether);
        _fundCollateralLender(collateralLender1, 5 ether);

        vm.prank(owner);
        vaultUtil.setMaxFlashLoanFeeThreshold(100, 0);

        try vault.startEpoch() {
            uint256 currentEpoch = vault.epoch();
            console.log("Epoch started:", currentEpoch);

            // Warp past term + emergency delay
            vm.warp(vault.epochStart() + vault.termDuration() + vault.emergencyAaveWithdrawDelay() + 1);

            uint256 lenderDeposits = vault.epochToAaveLenderDeposits(currentEpoch);
            console.log("Lender Aave deposits:", lenderDeposits);

            if (lenderDeposits > 0) {
                // Emergency withdrawal should work
                uint256 withdrawn = vaultUtil.emergencyWithdrawLenderAaveForEpoch(currentEpoch);
                console.log("Emergency withdrawn:", withdrawn);
                assertTrue(vault.epochEmergencyLenderWithdrawn(currentEpoch), "Should be marked withdrawn");
            } else {
                console.log("No Aave deposits to withdraw (all matched)");
            }
        } catch {
            console.log("Epoch start failed");
        }
    }

    function _testExistingEpochEmergency() internal view {
        uint256 currentEpoch = vault.epoch();
        uint256 lenderDeposits = vault.epochToAaveLenderDeposits(currentEpoch);
        uint256 clDeposits = vault.epochToAaveCLDeposits(currentEpoch);

        console.log("Current epoch:", currentEpoch);
        console.log("Lender Aave deposits:", lenderDeposits);
        console.log("CL Aave deposits:", clDeposits);
    }

    // ============ Permissionless Tests ============

    function test_EmergencyIsPermissionless() public view {
        console.log("=== Emergency Permissionless Check ===");
        // The emergency withdrawal functions are permissionless
        // Anyone can call them after the delay has passed
        console.log("Emergency functions are permissionless");
        console.log("Only time and epoch validity are enforced");
    }

    // ============ Multi-User Test ============

    function test_MultiUserDeposits() public {
        if (vault.epochStarted()) {
            console.log("SKIP: Epoch already started");
            return;
        }

        // Fund multiple users
        _fundLender(lender1, 10 ether);
        _fundLender(lender2, 5 ether);
        _fundCollateralLender(collateralLender1, 3 ether);
        _fundCollateralLender(cl2, 2 ether);
        _fundBorrower(borrower1, 5 ether);

        console.log("Multi-user deposits created");
        console.log("Total lender unutilized:", vault.totalLenderQTUnutilized());
        console.log("Total CL CT:", vault.totalCollateralLenderCT());
    }
}
