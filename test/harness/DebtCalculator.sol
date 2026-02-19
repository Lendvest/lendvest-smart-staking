// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title DebtCalculator
 * @notice Test utilities for debt and interest calculations
 * @dev Provides:
 *      1. Simple interest calculations
 *      2. Compound interest calculations
 *      3. APR/APY conversions
 *      4. Term-based interest
 */
contract DebtCalculator {

    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant WAD = 1e18;

    /**
     * @notice Calculate simple interest for a period
     * @param principal The principal amount
     * @param ratePerYear Annual interest rate (1e18 = 100%)
     * @param durationSeconds Duration in seconds
     * @return interest The interest amount
     */
    function calculateSimpleInterest(
        uint256 principal,
        uint256 ratePerYear,
        uint256 durationSeconds
    ) public pure returns (uint256) {
        return (principal * ratePerYear * durationSeconds) / (SECONDS_PER_YEAR * WAD);
    }

    /**
     * @notice Calculate total amount due (principal + interest)
     * @param principal The principal amount
     * @param ratePerYear Annual interest rate (1e18 = 100%)
     * @param durationSeconds Duration in seconds
     * @return totalDue Principal plus interest
     */
    function calculateTotalDue(
        uint256 principal,
        uint256 ratePerYear,
        uint256 durationSeconds
    ) public pure returns (uint256) {
        uint256 interest = calculateSimpleInterest(principal, ratePerYear, durationSeconds);
        return principal + interest;
    }

    /**
     * @notice Calculate interest for a 7-day term (default term duration)
     * @param principal The principal amount
     * @param ratePerYear Annual interest rate (1e18 = 100%)
     * @return interest Interest for 7 days
     */
    function calculate7DayInterest(
        uint256 principal,
        uint256 ratePerYear
    ) public pure returns (uint256) {
        return calculateSimpleInterest(principal, ratePerYear, 7 days);
    }

    /**
     * @notice Calculate interest for a 28-day term
     * @param principal The principal amount
     * @param ratePerYear Annual interest rate (1e18 = 100%)
     * @return interest Interest for 28 days
     */
    function calculate28DayInterest(
        uint256 principal,
        uint256 ratePerYear
    ) public pure returns (uint256) {
        return calculateSimpleInterest(principal, ratePerYear, 28 days);
    }

    /**
     * @notice Convert APR to per-second rate
     * @param aprPerYear Annual rate (1e18 = 100%)
     * @return ratePerSecond Rate per second
     */
    function aprToPerSecond(uint256 aprPerYear) public pure returns (uint256) {
        return aprPerYear / SECONDS_PER_YEAR;
    }

    /**
     * @notice Calculate lender's expected return
     * @param lenderDeposit Lender's WETH deposit
     * @param totalLenderPool Total lender pool size
     * @param totalBorrowed Total borrowed from lender pool
     * @param ratePerYear Annual interest rate
     * @param durationSeconds Loan duration
     * @return lenderReturn Expected return for this lender
     */
    function calculateLenderReturn(
        uint256 lenderDeposit,
        uint256 totalLenderPool,
        uint256 totalBorrowed,
        uint256 ratePerYear,
        uint256 durationSeconds
    ) public pure returns (uint256) {
        if (totalLenderPool == 0) return 0;

        // Lender's share of the pool
        uint256 lenderShare = (lenderDeposit * WAD) / totalLenderPool;

        // Total interest earned by pool
        uint256 totalInterest = calculateSimpleInterest(totalBorrowed, ratePerYear, durationSeconds);

        // Lender's portion of interest
        return (totalInterest * lenderShare) / WAD;
    }

    /**
     * @notice Calculate borrower's interest obligation
     * @param borrowerDebt Borrower's debt amount
     * @param ratePerYear Annual interest rate
     * @param durationSeconds Loan duration
     * @return interestOwed Interest the borrower owes
     */
    function calculateBorrowerInterest(
        uint256 borrowerDebt,
        uint256 ratePerYear,
        uint256 durationSeconds
    ) public pure returns (uint256) {
        return calculateSimpleInterest(borrowerDebt, ratePerYear, durationSeconds);
    }

    /**
     * @notice Validate interest calculation matches expected
     * @param actual Actual interest calculated by contract
     * @param expected Expected interest from this calculator
     * @param toleranceBps Tolerance in basis points (100 = 1%)
     * @return isValid Whether actual is within tolerance of expected
     */
    function validateInterest(
        uint256 actual,
        uint256 expected,
        uint256 toleranceBps
    ) public pure returns (bool) {
        if (expected == 0) return actual == 0;

        uint256 diff = actual > expected ? actual - expected : expected - actual;
        uint256 tolerance = (expected * toleranceBps) / 10000;

        return diff <= tolerance;
    }
}
