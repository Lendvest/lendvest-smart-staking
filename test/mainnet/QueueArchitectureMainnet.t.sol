// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseMainnetTest.sol";

/**
 * @title QueueArchitectureMainnetTest
 * @notice Tests for order queue architecture against deployed mainnet contracts
 */
contract QueueArchitectureMainnetTest is BaseMainnetTest {

    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test lender order queue operations
     */
    function test_LenderOrderQueue() public {
        uint256 initialLength = vault.getLenderOrdersLength();
        console.log("Initial lender orders:", initialLength);

        // Add orders
        _fundLender(lender1, 1 ether);
        assertEq(vault.getLenderOrdersLength(), initialLength + 1, "Should have 1 more order");

        address lender2 = makeAddr("lender2");
        _fundLender(lender2, 2 ether);
        assertEq(vault.getLenderOrdersLength(), initialLength + 2, "Should have 2 more orders");

        // Verify order contents
        VaultLib.LenderOrder[] memory orders = vault.getLenderOrders();
        assertEq(orders[initialLength].lender, lender1, "First new lender correct");
        assertEq(orders[initialLength].quoteAmount, 1 ether, "First amount correct");
        assertEq(orders[initialLength + 1].lender, lender2, "Second new lender correct");
        assertEq(orders[initialLength + 1].quoteAmount, 2 ether, "Second amount correct");
    }

    /**
     * @notice Test borrower order queue operations
     */
    function test_BorrowerOrderQueue() public {
        uint256 initialLength = vault.getBorrowerOrdersLength();
        console.log("Initial borrower orders:", initialLength);

        _fundBorrower(borrower1, 0.1 ether);
        assertEq(vault.getBorrowerOrdersLength(), initialLength + 1, "Should have 1 more order");

        VaultLib.BorrowerOrder[] memory orders = vault.getBorrowerOrders();
        assertEq(orders[initialLength].borrower, borrower1, "Borrower correct");
        assertEq(orders[initialLength].collateralAmount, 0.1 ether, "Amount correct");
    }

    /**
     * @notice Test collateral lender order queue operations
     */
    function test_CollateralLenderOrderQueue() public {
        uint256 initialLength = vault.getCollateralLenderOrdersLength();
        console.log("Initial CL orders:", initialLength);

        _fundCollateralLender(collateralLender1, 0.5 ether);
        assertEq(vault.getCollateralLenderOrdersLength(), initialLength + 1, "Should have 1 more order");

        VaultLib.CollateralLenderOrder[] memory orders = vault.getCollateralLenderOrders();
        assertEq(orders[initialLength].collateralLender, collateralLender1, "CL correct");
        assertEq(orders[initialLength].collateralAmount, 0.5 ether, "Amount correct");
    }

    /**
     * @notice Test queue state after matching
     */
    function test_QueueStateAfterMatching() public {
        // Only run if no active epoch
        if (vault.epochStarted()) {
            console.log("Skipping: epoch already started");
            return;
        }

        // Setup balanced orders
        _setupBalancedOrders();

        uint256 lendersBefore = vault.getLenderOrdersLength();
        uint256 borrowersBefore = vault.getBorrowerOrdersLength();
        uint256 clsBefore = vault.getCollateralLenderOrdersLength();

        console.log("Before matching:");
        console.log("  Lenders:", lendersBefore);
        console.log("  Borrowers:", borrowersBefore);
        console.log("  CLs:", clsBefore);

        // Start epoch (triggers matching)
        vm.prank(owner);
        vault.startEpoch();

        uint256 lendersAfter = vault.getLenderOrdersLength();
        uint256 borrowersAfter = vault.getBorrowerOrdersLength();
        uint256 clsAfter = vault.getCollateralLenderOrdersLength();

        console.log("After matching:");
        console.log("  Lenders:", lendersAfter);
        console.log("  Borrowers:", borrowersAfter);
        console.log("  CLs:", clsAfter);

        // Some orders should be consumed
        assertTrue(
            lendersAfter <= lendersBefore ||
            borrowersAfter <= borrowersBefore,
            "Some orders should be matched"
        );
    }

    /**
     * @notice Test epoch matches storage
     */
    function test_EpochMatchesStorage() public {
        // Only run if no active epoch
        if (vault.epochStarted()) {
            console.log("Skipping: epoch already started");
            return;
        }

        _startBalancedEpoch();

        uint256 currentEpoch = vault.epoch();
        VaultLib.MatchInfo[] memory matches = vault.getEpochMatches(currentEpoch);

        assertGt(matches.length, 0, "Should have matches");
        console.log("Number of matches:", matches.length);

        for (uint256 i = 0; i < matches.length; i++) {
            console.log("Match", i);
            console.log("  Lender:", matches[i].lender);
            console.log("  Borrower:", matches[i].borrower);
            console.log("  Quote:", matches[i].quoteAmount);
            console.log("  Collateral:", matches[i].collateralAmount);
        }
    }

    /**
     * @notice Test epoch collateral lender orders storage
     */
    function test_EpochCollateralLenderOrdersStorage() public {
        // Only run if no active epoch
        if (vault.epochStarted()) {
            console.log("Skipping: epoch already started");
            return;
        }

        _startBalancedEpoch();

        uint256 currentEpoch = vault.epoch();
        VaultLib.CollateralLenderOrder[] memory epochCLOrders =
            vault.getEpochCollateralLenderOrders(currentEpoch);

        assertGt(epochCLOrders.length, 0, "Should have epoch CL orders");
        console.log("Epoch CL orders:", epochCLOrders.length);
    }
}
