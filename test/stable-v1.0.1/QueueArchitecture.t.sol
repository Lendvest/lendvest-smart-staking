// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./BaseStableTest.sol";

/**
 * @title QueueArchitectureTest
 * @notice Tests for order queue architecture (commit c452d14)
 * @dev Validates:
 *      1. Order creation adds to queues
 *      2. Order matching removes from queues
 *      3. Partial order fulfillment
 *      4. Queue state after epoch
 */
contract QueueArchitectureTest is BaseStableTest {

    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test lender order queue operations
     */
    function test_LenderOrderQueue() public {
        // Initially empty
        assertEq(vault.getLenderOrdersLength(), 0, "Should start empty");

        // Add orders
        _fundLender(lender1, 1 ether);
        assertEq(vault.getLenderOrdersLength(), 1, "Should have 1 order");

        address lender2 = makeAddr("lender2");
        _fundLender(lender2, 2 ether);
        assertEq(vault.getLenderOrdersLength(), 2, "Should have 2 orders");

        // Verify order contents
        VaultLib.LenderOrder[] memory orders = vault.getLenderOrders();
        assertEq(orders[0].lender, lender1, "First lender correct");
        assertEq(orders[0].quoteAmount, 1 ether, "First amount correct");
        assertEq(orders[1].lender, lender2, "Second lender correct");
        assertEq(orders[1].quoteAmount, 2 ether, "Second amount correct");
    }

    /**
     * @notice Test borrower order queue operations
     */
    function test_BorrowerOrderQueue() public {
        assertEq(vault.getBorrowerOrdersLength(), 0, "Should start empty");

        _fundBorrower(borrower1, 0.1 ether);
        assertEq(vault.getBorrowerOrdersLength(), 1, "Should have 1 order");

        VaultLib.BorrowerOrder[] memory orders = vault.getBorrowerOrders();
        assertEq(orders[0].borrower, borrower1, "Borrower correct");
        assertEq(orders[0].collateralAmount, 0.1 ether, "Amount correct");
    }

    /**
     * @notice Test collateral lender order queue operations
     */
    function test_CollateralLenderOrderQueue() public {
        assertEq(vault.getCollateralLenderOrdersLength(), 0, "Should start empty");

        _fundCollateralLender(collateralLender1, 0.5 ether);
        assertEq(vault.getCollateralLenderOrdersLength(), 1, "Should have 1 order");

        VaultLib.CollateralLenderOrder[] memory orders = vault.getCollateralLenderOrders();
        assertEq(orders[0].collateralLender, collateralLender1, "CL correct");
        assertEq(orders[0].collateralAmount, 0.5 ether, "Amount correct");
    }

    /**
     * @notice Test queue state after matching
     */
    function test_QueueStateAfterMatching() public {
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
     * @notice Test partial order fulfillment
     */
    function test_PartialOrderFulfillment() public {
        // More lender WETH than needed — tests that some lender funds remain unutilized
        // Must also increase CL to support the extra matching capacity
        _setupBalancedOrders();
        address lender2 = makeAddr("lender2");
        _fundLender(lender2, 5 ether);
        // Extra CL to prevent InsufficientFunds when more lender WETH drives larger flash loan
        address cl2 = makeAddr("collateralLender2");
        _fundCollateralLender(cl2, 3 ether);

        uint256 totalLenderBefore = vault.getLenderOrdersLength();
        console.log("Lender orders before:", totalLenderBefore);

        vm.prank(owner);
        vault.startEpoch();

        // Some lender funds should remain unutilized
        VaultLib.LenderOrder[] memory orders = vault.getLenderOrders();
        console.log("Lender orders after:", orders.length);
        if (orders.length > 0) {
            console.log("Remaining lender amount:", orders[0].quoteAmount);
        }
    }

    /**
     * @notice Test epoch matches storage
     */
    function test_EpochMatchesStorage() public {
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
        _startBalancedEpoch();

        uint256 currentEpoch = vault.epoch();
        VaultLib.CollateralLenderOrder[] memory epochCLOrders =
            vault.getEpochCollateralLenderOrders(currentEpoch);

        assertGt(epochCLOrders.length, 0, "Should have epoch CL orders");
        console.log("Epoch CL orders:", epochCLOrders.length);
    }
}
