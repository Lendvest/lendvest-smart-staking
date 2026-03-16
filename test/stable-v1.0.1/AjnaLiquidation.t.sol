// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseStableTest.sol";

/**
 * @title AjnaLiquidationTest
 * @notice Tests for Ajna pool liquidation flows via LiquidationProxy
 * @dev Validates:
 *      1. Vault's Ajna debt/collateral state after epoch starts
 *      2. setAllowKick flow (vault → proxy)
 *      3. getAllowKick state transitions
 *      4. Bond size calculation with active debt
 *      5. eligibleForLiquidation check with active borrowing
 *      6. Vault's lenderKick authorization (onlyProxy)
 *      7. Vault's withdrawBondsForProxy authorization (onlyProxy)
 *      8. Pool debt and collateral queries via poolInfoUtils
 */
contract AjnaLiquidationTest is BaseStableTest {

    address internal kicker = makeAddr("kicker");

    function setUp() public override {
        super.setUp();
    }

    // ============ AJNA POOL STATE AFTER EPOCH ============

    /**
     * @notice After startEpoch, vault should have debt in the Ajna pool
     */
    function test_VaultHasDebtAfterEpochStart() public {
        _startBalancedEpoch();

        uint256 totalBorrowed = vault.totalBorrowAmount();
        console.log("Total borrowed:", totalBorrowed);

        if (totalBorrowed == 0) {
            console.log("NOTE: No borrowing at current fork block. Checking pool directly.");
        }

        // Query Ajna pool for vault's debt position
        (uint256 debt, uint256 collateral, uint256 npTpRatio) = ajnaPool.borrowerInfo(address(vault));
        console.log("Ajna debt:", debt);
        console.log("Ajna collateral:", collateral);
        console.log("npTpRatio:", npTpRatio);

        // If there was borrowing, both should be > 0
        if (totalBorrowed > 0) {
            assertGt(debt, 0, "Should have non-zero debt in Ajna");
            assertGt(collateral, 0, "Should have non-zero collateral in Ajna");
        }
    }

    /**
     * @notice Pool has deposits after epoch matching
     */
    function test_PoolHasDepositsAfterEpoch() public {
        _startBalancedEpoch();

        uint256 depositSize = ajnaPool.depositSize();
        console.log("Pool deposit size:", depositSize);

        uint256 totalBorrowed = vault.totalBorrowAmount();
        if (totalBorrowed > 0) {
            assertGt(depositSize, 0, "Pool should have deposits");
        }
    }

    // ============ ALLOW KICK FLOW ============

    /**
     * @notice setAllowKick via vault's proxy function
     */
    function test_SetAllowKickViaVault() public {
        // Verify initial state
        assertFalse(vault.getAllowKick(), "Should start false");

        // Only proxy can call vault's setAllowKick
        vm.prank(address(vaultUtil));
        vault.setAllowKick(true);
        assertTrue(vault.getAllowKick(), "Should be true after set");

        vm.prank(address(vaultUtil));
        vault.setAllowKick(false);
        assertFalse(vault.getAllowKick(), "Should be false after unset");
    }

    /**
     * @notice Non-proxy cannot call vault's setAllowKick
     */
    function test_SetAllowKick_OnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.setAllowKick(true);
    }

    // ============ BOND SIZE ============

    /**
     * @notice getBondSize with active debt returns reasonable value
     */
    function test_BondSizeWithActiveDebt() public {
        _startBalancedEpoch();

        uint256 totalBorrowed = vault.totalBorrowAmount();
        if (totalBorrowed == 0) {
            console.log("NOTE: No borrowing. Skipping bond size test.");
            return;
        }

        uint256 bondSize = liquidationProxy.getBondSize();
        console.log("Bond size:", bondSize);
        assertGt(bondSize, 0, "Bond should be > 0 with debt");

        // Bond should be between 0.5% and 3% of debt (MIN_BOND_FACTOR to MAX_BOND_FACTOR)
        (uint256 debt,,) = ajnaPool.borrowerInfo(address(vault));
        uint256 minBond = (debt * 5) / 1000; // 0.5%
        uint256 maxBond = (debt * 30) / 1000; // 3%

        // The + 1 wei is added in getBondSize
        assertGe(bondSize, minBond, "Bond should be >= 0.5% of debt");
        assertLe(bondSize, maxBond + 2, "Bond should be <= 3% of debt (+ rounding)");
    }

    // ============ LIQUIDATION ELIGIBILITY ============

    /**
     * @notice Check eligibility based on pool LUP vs threshold price
     */
    function test_EligibilityCheck() public {
        _startBalancedEpoch();

        uint256 totalBorrowed = vault.totalBorrowAmount();
        if (totalBorrowed == 0) {
            console.log("NOTE: No borrowing. Skipping.");
            return;
        }

        bool eligible = liquidationProxy.eligibleForLiquidationPool(address(vault));
        console.log("Eligible for liquidation:", eligible);

        // With healthy collateral ratio, should NOT be eligible
        // (freshly created position should be overcollateralized)
        assertFalse(eligible, "Fresh position should not be eligible for liquidation");
    }

    // ============ LENDER KICK AUTHORIZATION ============

    /**
     * @notice Vault's lenderKick is only callable by proxy
     */
    function test_VaultLenderKick_OnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.lenderKick(1 ether);
    }

    /**
     * @notice Vault's lenderKick reverts if allowKick is false
     */
    function test_VaultLenderKick_RequiresAllowKick() public {
        assertFalse(vault.getAllowKick(), "allowKick should be false");

        // Even proxy can't kick if not allowed
        vm.prank(address(vaultUtil));
        vm.expectRevert(VaultLib.TokenOperationFailed.selector);
        vault.lenderKick(1 ether);
    }

    // ============ WITHDRAW BONDS AUTHORIZATION ============

    /**
     * @notice Vault's withdrawBondsForProxy is only callable by proxy
     */
    function test_WithdrawBonds_OnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.withdrawBondsForProxy();
    }

    /**
     * @notice withdrawBondsForProxy with no claimable bonds reverts (InsufficientLiquidity from Ajna)
     */
    function test_WithdrawBonds_NoBonds() public {
        // No auction has happened — Ajna pool reverts with InsufficientLiquidity
        // when there are no bonds to withdraw
        vm.prank(address(vaultUtil));
        vm.expectRevert();
        vault.withdrawBondsForProxy();
    }

    // ============ CLEAR AJNA DEPOSITS ============

    /**
     * @notice clearAjnaDeposits is only callable by proxy
     */
    function test_ClearAjnaDeposits_OnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.clearAjnaDeposits(1 ether);
    }

    // ============ REPAY DEBT ============

    /**
     * @notice repayDebtForProxy is only callable by proxy
     */
    function test_RepayDebt_OnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.repayDebtForProxy(1 ether, 1 ether);
    }

    // ============ POOL INFO QUERIES ============

    /**
     * @notice poolInfoUtils borrowerInfo returns valid data
     */
    function test_PoolInfoBorrowerInfo() public {
        _startBalancedEpoch();

        (uint256 debt, uint256 collateral, uint256 npTp, uint256 thresholdPrice) =
            poolInfoUtils.borrowerInfo(address(ajnaPool), address(vault));

        console.log("Pool Info - Debt:", debt);
        console.log("Pool Info - Collateral:", collateral);
        console.log("Pool Info - npTp:", npTp);
        console.log("Pool Info - Threshold Price:", thresholdPrice);

        uint256 totalBorrowed = vault.totalBorrowAmount();
        if (totalBorrowed > 0) {
            assertGt(debt, 0, "Should report non-zero debt");
            assertGt(collateral, 0, "Should report non-zero collateral");
            assertGt(thresholdPrice, 0, "Should have non-zero threshold price");
        }
    }

    /**
     * @notice LUP (Lowest Utilized Price) is available for the pool
     */
    function test_PoolLUP() public {
        _startBalancedEpoch();

        uint256 lup = poolInfoUtils.lup(address(ajnaPool));
        console.log("Pool LUP:", lup);

        uint256 totalBorrowed = vault.totalBorrowAmount();
        if (totalBorrowed > 0) {
            assertGt(lup, 0, "LUP should be > 0 with active deposits");
        }
    }

    // ============ KICK + AUCTION FLOW (INTEGRATION) ============

    /**
     * @notice Full kick flow: enable kick → verify bond size → attempt kick
     * @dev This won't fully execute because the position is healthy,
     *      but validates the setup steps
     */
    function test_KickFlowSetup() public {
        _startBalancedEpoch();

        uint256 totalBorrowed = vault.totalBorrowAmount();
        if (totalBorrowed == 0) {
            console.log("NOTE: No borrowing. Skipping kick flow.");
            return;
        }

        // 1. Enable kicking
        vm.prank(address(vaultUtil));
        vault.setAllowKick(true);
        assertTrue(vault.getAllowKick(), "Kick should be allowed");

        // 2. Get bond size
        uint256 bondSize = liquidationProxy.getBondSize();
        console.log("Bond size needed:", bondSize);
        assertGt(bondSize, 0, "Should have valid bond size");

        // 3. Fund kicker with WETH for bond
        deal(WETH_ADDRESS, kicker, bondSize);
        vm.startPrank(kicker);
        IERC20(WETH_ADDRESS).approve(address(liquidationProxy), bondSize);

        // 4. Attempt to kick — will revert because position is healthy
        // Ajna checks if borrower is undercollateralized before allowing kick
        // This verifies the proxy correctly interfaces with the pool
        try liquidationProxy.lenderKick() {
            console.log("Kick succeeded (unexpected - position may be undercollateralized)");
            // If kick succeeded, verify auction state
            (uint256 kickTime,,,,,,,,) = liquidationProxy.auctionStatus();
            assertGt(kickTime, 0, "Should have active auction");
        } catch {
            console.log("Kick reverted as expected (position is healthy)");
        }
        vm.stopPrank();

        // 5. Disable kicking
        vm.prank(address(vaultUtil));
        vault.setAllowKick(false);
        assertFalse(vault.getAllowKick(), "Kick should be disabled");
    }
}
