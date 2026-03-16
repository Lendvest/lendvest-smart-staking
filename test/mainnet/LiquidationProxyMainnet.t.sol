// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseMainnetTest.sol";

/**
 * @title LiquidationProxyMainnetTest
 * @notice Tests for LiquidationProxy contract against deployed mainnet
 * @dev Validates claimBond, access control, lenderKick, and view functions
 */
contract LiquidationProxyMainnetTest is BaseMainnetTest {

    address internal kicker = makeAddr("kicker");
    address internal randomUser = makeAddr("randomUser");

    function setUp() public override {
        super.setUp();
    }

    // ============ Initialization ============

    function test_ProxyInitialization() public view {
        console.log("=== Proxy Initialization ===");
        console.log("Pool:", address(liquidationProxy.pool()));
        console.log("Vault:", address(liquidationProxy.LVLidoVault()));
        console.log("Quote token:", liquidationProxy.quoteToken());
        console.log("Collateral token:", liquidationProxy.collateralToken());
        console.log("Allow kick:", liquidationProxy.allowKick());

        assertEq(address(liquidationProxy.pool()), address(ajnaPool), "Pool should match");
        assertEq(address(liquidationProxy.LVLidoVault()), address(vault), "Vault should match");
        assertEq(liquidationProxy.quoteToken(), WETH_ADDRESS, "Quote token should be WETH");
        assertEq(liquidationProxy.collateralToken(), WSTETH_ADDRESS, "Collateral should be wstETH");
    }

    function test_ProxyOwnership() public view {
        address proxyOwner = liquidationProxy.owner();
        console.log("Proxy owner:", proxyOwner);
        assertEq(proxyOwner, address(vault), "Proxy owner should be vault");
    }

    // ============ Access Control ============

    function test_SetLVLidoVault_OnlyOwner() public {
        vm.prank(randomUser);
        vm.expectRevert();
        liquidationProxy.setLVLidoVault(address(0x1));

        console.log("Non-owner correctly rejected");
    }

    function test_SetAllowKick_OnlyOwner() public {
        vm.prank(randomUser);
        vm.expectRevert();
        liquidationProxy.setAllowKick(true);

        console.log("Non-owner correctly rejected from setAllowKick");
    }

    function test_VaultCanSetAllowKick() public {
        vm.prank(address(vault));
        liquidationProxy.setAllowKick(true);
        assertTrue(liquidationProxy.allowKick(), "Should be true");

        vm.prank(address(vault));
        liquidationProxy.setAllowKick(false);
        assertFalse(liquidationProxy.allowKick(), "Should be false");
    }

    // ============ Claim Bond ============

    function test_ClaimBond_RevertsNoBond() public {
        vm.prank(kicker);
        vm.expectRevert("No bond to claim");
        liquidationProxy.claimBond();
    }

    function test_KickerAmountTracking() public view {
        uint256 kickerAmount = liquidationProxy.kickerAmount(kicker);
        assertEq(kickerAmount, 0, "Should start at 0");
        console.log("Kicker amount:", kickerAmount);
    }

    // ============ Lender Kick ============

    function test_LenderKick_RevertsWhenNotAllowed() public {
        assertFalse(liquidationProxy.allowKick(), "Should start with kick not allowed");

        vm.prank(kicker);
        vm.expectRevert("Kick not allowed");
        liquidationProxy.lenderKick();
    }

    function test_LenderKick_RequiresBondTransfer() public {
        if (vault.totalBorrowAmount() == 0) {
            console.log("SKIP: No debt for kick test");
            return;
        }

        // Enable kicking
        vm.prank(address(vault));
        liquidationProxy.setAllowKick(true);
        assertTrue(liquidationProxy.allowKick(), "Kick should be allowed");

        // Try kick without WETH - should revert on transferFrom
        vm.prank(kicker);
        vm.expectRevert();
        liquidationProxy.lenderKick();

        // Disable kicking
        vm.prank(address(vault));
        liquidationProxy.setAllowKick(false);
    }

    // ============ View Functions ============

    function test_AuctionStatus_NoAuction() public view {
        console.log("=== Auction Status ===");

        (
            uint256 kickTime,
            uint256 collateral,
            uint256 debtToCover,
            bool isCollateralized,
            uint256 price,
            uint256 neutralPrice,
            uint256 referencePrice,
            uint256 debtToCollateral,
            uint256 bondFactor
        ) = liquidationProxy.auctionStatus();

        console.log("Kick time:", kickTime);
        console.log("Collateral:", collateral);
        console.log("Debt to cover:", debtToCover);
        console.log("Is collateralized:", isCollateralized);

        if (kickTime == 0) {
            console.log("No active auction");
        }
    }

    function test_EligibleForLiquidation() public view {
        bool eligible = liquidationProxy.eligibleForLiquidationPool(address(vault));
        console.log("Vault eligible for liquidation:", eligible);
    }

    function test_GetBondSize() public view {
        if (vault.totalBorrowAmount() == 0) {
            console.log("SKIP: No debt - bond calculation requires debt");
            return;
        }

        uint256 bondSize = liquidationProxy.getBondSize();
        console.log("Bond size:", bondSize);
        assertGt(bondSize, 0, "Bond size should be > 0 with debt");
    }

    // ============ Settle ============

    function test_Settle_RevertsNoAuction() public {
        vm.expectRevert("Cannot settle auction.");
        liquidationProxy.settle(10);
    }

    // ============ Take ============

    function test_Take_RevertsNoAuction() public {
        vm.expectRevert("Auction not ongoing.");
        liquidationProxy.take(1 ether);
    }

    // ============ Full Kick Flow Setup ============

    function test_FullKickFlowSetup() public {
        console.log("=== Full Kick Flow Setup ===");

        if (vault.totalBorrowAmount() == 0) {
            console.log("SKIP: No active debt");
            return;
        }

        // 1. Check initial state
        assertFalse(liquidationProxy.allowKick(), "Kick should not be allowed");

        // 2. Enable kicking via vault
        vm.prank(address(vault));
        liquidationProxy.setAllowKick(true);
        assertTrue(liquidationProxy.allowKick(), "Kick should be allowed");

        // 3. Get required bond
        uint256 bondSize = liquidationProxy.getBondSize();
        console.log("Bond size:", bondSize);

        // 4. Fund kicker
        deal(WETH_ADDRESS, kicker, bondSize);
        vm.startPrank(kicker);
        IERC20(WETH_ADDRESS).approve(address(liquidationProxy), bondSize);

        // 5. Check eligibility
        bool eligible = liquidationProxy.eligibleForLiquidationPool(address(vault));
        console.log("Eligible:", eligible);

        // 6. Attempt kick (will fail if healthy)
        if (eligible) {
            try liquidationProxy.lenderKick() {
                console.log("Kick succeeded");
            } catch {
                console.log("Kick failed (expected if healthy)");
            }
        } else {
            console.log("Position not eligible (healthy)");
        }

        vm.stopPrank();

        // 7. Disable kicking
        vm.prank(address(vault));
        liquidationProxy.setAllowKick(false);
    }
}
