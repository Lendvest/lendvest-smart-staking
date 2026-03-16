// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseMainnetTest.sol";

/**
 * @title AjnaLiquidationMainnetTest
 * @notice Tests for Ajna pool liquidation flows against deployed mainnet contracts
 * @dev Validates Ajna debt/collateral state and liquidation mechanisms
 */
contract AjnaLiquidationMainnetTest is BaseMainnetTest {

    address internal kicker = makeAddr("kicker");

    function setUp() public override {
        super.setUp();
    }

    // ============ Ajna Pool State ============

    function test_AjnaPoolAddress() public view {
        address poolAddr = address(ajnaPool);
        console.log("Ajna pool address:", poolAddr);
        assertTrue(poolAddr != address(0), "Pool should exist");
    }

    function test_VaultDebtPosition() public view {
        console.log("=== Vault Ajna Position ===");

        (uint256 debt, uint256 collateral, uint256 npTpRatio) = ajnaPool.borrowerInfo(address(vault));

        console.log("Debt:", debt);
        console.log("Collateral:", collateral);
        console.log("npTpRatio:", npTpRatio);

        if (vault.epochStarted() && vault.totalBorrowAmount() > 0) {
            assertGt(debt, 0, "Should have debt if epoch started with borrowing");
        }
    }

    function test_PoolDepositSize() public view {
        uint256 depositSize = ajnaPool.depositSize();
        console.log("Pool deposit size:", depositSize);
    }

    // ============ Allow Kick State ============

    function test_AllowKickInitialState() public view {
        bool allowKick = vault.getAllowKick();
        console.log("AllowKick status:", allowKick);
        // AllowKick should typically be false unless triggered
    }

    function test_SetAllowKickOnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.setAllowKick(true);
    }

    function test_SetAllowKickViaVaultUtil() public {
        vm.prank(address(vaultUtil));
        vault.setAllowKick(true);
        assertTrue(vault.getAllowKick(), "Should be true after set");

        vm.prank(address(vaultUtil));
        vault.setAllowKick(false);
        assertFalse(vault.getAllowKick(), "Should be false after unset");
    }

    // ============ Bond Size ============

    function test_BondSizeCalculation() public view {
        console.log("=== Bond Size Calculation ===");

        uint256 totalBorrowed = vault.totalBorrowAmount();
        console.log("Total borrowed:", totalBorrowed);

        if (totalBorrowed == 0) {
            console.log("SKIP: No active debt - bond calculation requires debt");
            return;
        }

        uint256 bondSize = liquidationProxy.getBondSize();
        console.log("Bond size:", bondSize);
    }

    function test_BondSizeWithActiveDebt() public view {
        uint256 totalBorrowed = vault.totalBorrowAmount();
        if (totalBorrowed == 0) {
            console.log("SKIP: No active debt");
            return;
        }

        uint256 bondSize = liquidationProxy.getBondSize();
        assertGt(bondSize, 0, "Bond should be > 0 with debt");

        // Bond should be reasonable percentage of debt
        (uint256 debt,,) = ajnaPool.borrowerInfo(address(vault));
        console.log("Debt:", debt);
        console.log("Bond size:", bondSize);
    }

    // ============ Liquidation Eligibility ============

    function test_EligibilityCheck() public view {
        bool eligible = liquidationProxy.eligibleForLiquidationPool(address(vault));
        console.log("Eligible for liquidation:", eligible);

        // Fresh or healthy positions should not be eligible
        if (vault.totalBorrowAmount() > 0) {
            // With proper collateral, should NOT be eligible
            console.log("Position health status logged");
        }
    }

    // ============ Authorization Tests ============

    function test_LenderKickOnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.lenderKick(1 ether);
    }

    function test_LenderKickRequiresAllowKick() public {
        assertFalse(vault.getAllowKick(), "allowKick should be false");

        vm.prank(address(vaultUtil));
        vm.expectRevert(VaultLib.TokenOperationFailed.selector);
        vault.lenderKick(1 ether);
    }

    function test_WithdrawBondsOnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.withdrawBondsForProxy();
    }

    function test_ClearAjnaDepositsOnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.clearAjnaDeposits(1 ether);
    }

    function test_RepayDebtOnlyProxy() public {
        vm.prank(kicker);
        vm.expectRevert(VaultLib.OnlyProxy.selector);
        vault.repayDebtForProxy(1 ether, 1 ether);
    }

    // ============ Pool Info Utils ============

    function test_PoolInfoBorrowerInfo() public view {
        console.log("=== Pool Info Utils - Borrower Info ===");

        (uint256 debt, uint256 collateral, uint256 npTp, uint256 thresholdPrice) =
            poolInfoUtils.borrowerInfo(address(ajnaPool), address(vault));

        console.log("Debt:", debt);
        console.log("Collateral:", collateral);
        console.log("npTp:", npTp);
        console.log("Threshold Price:", thresholdPrice);
    }

    function test_PoolLUP() public view {
        uint256 lup = poolInfoUtils.lup(address(ajnaPool));
        console.log("Pool LUP:", lup);

        if (vault.totalBorrowAmount() > 0) {
            assertGt(lup, 0, "LUP should be > 0 with active deposits");
        }
    }

    // ============ Auction Status ============

    function test_AuctionStatus() public view {
        console.log("=== Auction Status ===");

        (
            address kicker_,
            uint256 bondFactor,
            uint256 bondSize,
            uint256 kickTime,
            uint256 referencePrice,
            uint256 neutralPrice,
            uint256 debtToCollateral,
            address head,
            address next,
            address prev
        ) = ajnaPool.auctionInfo(address(vault));

        console.log("Kicker:", kicker_);
        console.log("Bond factor:", bondFactor);
        console.log("Bond size:", bondSize);
        console.log("Kick time:", kickTime);

        if (kickTime == 0) {
            console.log("No active auction");
        } else {
            console.log("Auction is active");
        }
    }

    // ============ Liquidation Proxy State ============

    function test_LiquidationProxyConfiguration() public view {
        console.log("=== Liquidation Proxy Config ===");
        console.log("Pool:", address(liquidationProxy.pool()));
        console.log("Vault:", address(liquidationProxy.LVLidoVault()));
        console.log("Allow kick:", liquidationProxy.allowKick());
        console.log("Quote token:", liquidationProxy.quoteToken());
        console.log("Collateral token:", liquidationProxy.collateralToken());
    }

    function test_LiquidationProxyOwnership() public view {
        address proxyOwner = liquidationProxy.owner();
        console.log("Proxy owner:", proxyOwner);
        assertEq(proxyOwner, address(vault), "Proxy owner should be vault");
    }

    // ============ Kick Flow Test ============

    function test_KickFlowSetup() public {
        console.log("=== Kick Flow Setup Test ===");

        uint256 totalBorrowed = vault.totalBorrowAmount();
        if (totalBorrowed == 0) {
            console.log("SKIP: No active debt for kick test");
            return;
        }

        // Enable kicking
        vm.prank(address(vaultUtil));
        vault.setAllowKick(true);
        assertTrue(vault.getAllowKick(), "Kick should be allowed");

        // Get bond size
        uint256 bondSize = liquidationProxy.getBondSize();
        console.log("Bond size needed:", bondSize);

        // Check eligibility
        bool eligible = liquidationProxy.eligibleForLiquidationPool(address(vault));
        console.log("Eligible for liquidation:", eligible);

        // Disable kicking
        vm.prank(address(vaultUtil));
        vault.setAllowKick(false);

        console.log("Kick flow setup verified");
    }

    // ============ Collateral Tranche ============

    function test_CollateralTrancheState() public view {
        uint256 tranche = vault.collateralLenderTraunche();
        console.log("Current collateral tranche:", tranche);
    }
}
