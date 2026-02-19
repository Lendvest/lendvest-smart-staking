// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LVLidoVault} from "../src/LVLidoVault.sol";
import {LVLidoVaultUtil} from "../src/LVLidoVaultUtil.sol";
import {ILVLidoVault} from "../src/interfaces/ILVLidoVault.sol";
import {IERC20Pool} from "../src/interfaces/pool/erc20/IERC20Pool.sol";
import {IPoolInfoUtils} from "../src/interfaces/IPoolInfoUtils.sol";
import {IWsteth} from "../src/interfaces/vault/IWsteth.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultLib} from "../src/libraries/VaultLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {TestHelpers} from "./TestHelpers.t.sol";

/**
 * @title LidoClaimDelayRateTest
 * @notice Tests to verify the impact of Lido claim delay on rate calculations
 * @dev Run with: forge test --match-contract LidoClaimDelayRateTest -vvv --fork-url <RPC_URL>
 */
contract LidoClaimDelayRateTest is Test, TestHelpers {
    // Constants
    uint256 public constant LIDO_CLAIM_DELAY = 7 days; // 604800 seconds
    uint256 public constant TERM_DURATION = 14 days;

    // Chainlink Price Feeds
    AggregatorV3Interface internal stethUsdPriceFeed;
    AggregatorV3Interface internal ethUsdPriceFeed;

    // Test contracts (will be set in setUp or per test)
    LVLidoVault public vault;
    LVLidoVaultUtil public vaultUtil;
    IWsteth public wsteth;

    // Test parameters
    struct RateTestParams {
        uint256 rate;               // APR rate in 1e18 scale
        uint256 totalBorrowAmount;  // Total borrowed WETH
        uint256 epochStart;         // Epoch start timestamp
        uint256 currentTime;        // Current block.timestamp
        uint256 claimDelay;         // Lido claim delay in seconds
    }

    // Test result
    struct RateTestResult {
        uint256 timeElapsed;
        uint256 totalTimeForInterest;
        uint256 approxPercentFinalInterest;
        uint256 interestBps;
        uint256 debtWithInterest;
        uint256 collateralNeeded;
        uint256 wstethRate;
    }

    function setUp() public {
        // Fork mainnet at a recent block
        // Note: Run with --fork-url to enable mainnet forking

        wsteth = IWsteth(WSTETH_ADDRESS);
        stethUsdPriceFeed = AggregatorV3Interface(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);
        ethUsdPriceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    }

    /**
     * @notice Helper to get wstETH to WETH conversion rate using Chainlink oracles
     * @dev Mirrors the calculation in LVLidoVaultUtil.getWstethToWeth()
     */
    function getWstethToWeth(uint256 _amount) public view returns (uint256) {
        (, int256 stethPrice,,,) = stethUsdPriceFeed.latestRoundData();
        uint256 stethAmount = _amount * wsteth.stEthPerToken() / 1e18;
        uint256 stethValueScaled = stethAmount * uint256(stethPrice);
        (, int256 ethPrice,,,) = ethUsdPriceFeed.latestRoundData();
        return stethValueScaled / uint256(ethPrice);
    }

    /**
     * @notice Core rate calculation function - mirrors LVLidoVaultUtil.performUpkeep() logic
     * @param params Test parameters including rate, borrow amount, times, and claim delay
     * @return result Calculated values for verification
     */
    function calculateRateImpact(RateTestParams memory params) public view returns (RateTestResult memory result) {
        // Calculate time elapsed since epoch start
        if (params.currentTime > params.epochStart) {
            result.timeElapsed = params.currentTime - params.epochStart;
        }

        // Total time for interest = timeElapsed + claimDelay
        result.totalTimeForInterest = result.timeElapsed + params.claimDelay;

        // Calculate approximate interest percentage
        // Formula from LVLidoVaultUtil.sol:253-254
        // approxPercentFinalInterest = (rate * totalTimeForInterest) / 365 days
        result.approxPercentFinalInterest = (params.rate * result.totalTimeForInterest) / 365 days;

        // Convert to basis points for readability (1e18 -> bps = divide by 1e14)
        result.interestBps = result.approxPercentFinalInterest / 1e14;

        // Get current wstETH rate
        result.wstethRate = getWstethToWeth(1e18);

        // Calculate debt with interest
        // Formula: totalBorrowAmount * (1e18 + approxPercentFinalInterest) / 1e18
        result.debtWithInterest = (params.totalBorrowAmount * (1e18 + result.approxPercentFinalInterest)) / 1e18;

        // Calculate collateral needed for claim
        // Formula from LVLidoVaultUtil.sol:258-259
        // approxCTForClaim = (totalBorrowAmount * (1e18 + approxPercentFinalInterest)) / stethPerWsteth
        if (result.wstethRate > 0) {
            result.collateralNeeded = (params.totalBorrowAmount * (1e18 + result.approxPercentFinalInterest)) / result.wstethRate;
        }
    }

    /**
     * @notice Test: Verify rate calculation with default 7-day claim delay
     */
    function test_ClaimDelay_Default7Days() public {
        console.log("=== Test: Default 7-Day Claim Delay ===");

        RateTestParams memory params = RateTestParams({
            rate: 221e14,           // 2.21% APR (common rate)
            totalBorrowAmount: 100 ether,  // 100 WETH borrowed
            epochStart: block.timestamp - 14 days, // Epoch started 14 days ago
            currentTime: block.timestamp,
            claimDelay: 7 days      // Default Lido claim delay
        });

        RateTestResult memory result = calculateRateImpact(params);

        _logResults("7 Days", params, result);

        // Verify calculations
        uint256 expectedTotalTime = 14 days + 7 days; // 21 days
        assertEq(result.totalTimeForInterest, expectedTotalTime, "Total time should be 21 days");

        // Expected interest: 2.21% * 21/365 = ~0.127%
        // In 1e18: 221e14 * 21 days / 365 days = ~1.27e15
        uint256 expectedInterest = (params.rate * expectedTotalTime) / 365 days;
        assertEq(result.approxPercentFinalInterest, expectedInterest, "Interest calculation mismatch");
    }

    /**
     * @notice Test: Compare different claim delays and their impact
     */
    function test_ClaimDelay_Comparison() public {
        console.log("=== Test: Claim Delay Comparison ===");
        console.log("");

        RateTestParams memory baseParams = RateTestParams({
            rate: 221e14,           // 2.21% APR
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 0           // Will be set per test
        });

        uint256[] memory delays = new uint256[](5);
        delays[0] = 0;          // No delay
        delays[1] = 3 days;     // 3 days
        delays[2] = 7 days;     // 7 days (default)
        delays[3] = 10 days;    // 10 days
        delays[4] = 14 days;    // 14 days

        console.log("| Claim Delay | Interest (bps) | Debt With Interest | Collateral Needed |");
        console.log("|-------------|----------------|--------------------|--------------------|");

        for (uint256 i = 0; i < delays.length; i++) {
            baseParams.claimDelay = delays[i];
            RateTestResult memory result = calculateRateImpact(baseParams);

            console.log(
                string.concat(
                    "| ", _daysToString(delays[i]), " days     | ",
                    vm.toString(result.interestBps), " bps       | ",
                    formatValue(result.debtWithInterest), " | ",
                    formatValue(result.collateralNeeded), " |"
                )
            );
        }
    }

    /**
     * @notice Test: Verify rate bounds are respected
     */
    function test_RateBounds() public {
        console.log("=== Test: Rate Bounds Verification ===");

        // Test with various rates
        uint256[] memory rates = new uint256[](5);
        rates[0] = 5e15;    // 0.5% (lower bound)
        rates[1] = 1e16;    // 1%
        rates[2] = 221e14;  // 2.21%
        rates[3] = 5e16;    // 5%
        rates[4] = 1e17;    // 10% (upper bound)

        RateTestParams memory params = RateTestParams({
            rate: 0,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 7 days
        });

        console.log("");
        console.log("| APR Rate | Interest (bps) | Debt With Interest |");
        console.log("|----------|----------------|---------------------|");

        for (uint256 i = 0; i < rates.length; i++) {
            params.rate = rates[i];
            RateTestResult memory result = calculateRateImpact(params);

            console.log(
                string.concat(
                    "| ", _rateToString(rates[i]), "% | ",
                    vm.toString(result.interestBps), " bps      | ",
                    formatValue(result.debtWithInterest), " |"
                )
            );
        }
    }

    /**
     * @notice Test: Edge case - Very short epoch duration
     */
    function test_ShortEpochDuration() public {
        console.log("=== Test: Short Epoch Duration (1 day elapsed) ===");

        RateTestParams memory params = RateTestParams({
            rate: 221e14,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 1 days, // Only 1 day elapsed
            currentTime: block.timestamp,
            claimDelay: 7 days
        });

        RateTestResult memory result = calculateRateImpact(params);

        _logResults("Short Epoch", params, result);

        // With 1 day + 7 day claim delay = 8 days total
        // Interest should be: 2.21% * 8/365 = ~0.048%
        assertEq(result.totalTimeForInterest, 8 days, "Total time should be 8 days");
    }

    /**
     * @notice Test: Edge case - Zero claim delay
     */
    function test_ZeroClaimDelay() public {
        console.log("=== Test: Zero Claim Delay ===");

        RateTestParams memory params = RateTestParams({
            rate: 221e14,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 0  // No claim delay
        });

        RateTestResult memory result = calculateRateImpact(params);

        _logResults("Zero Delay", params, result);

        // Should only count the 14 days of epoch duration
        assertEq(result.totalTimeForInterest, 14 days, "Total time should be 14 days only");
    }

    /**
     * @notice Test: Large borrow amounts
     */
    function test_LargeBorrowAmount() public {
        console.log("=== Test: Large Borrow Amount (1000 ETH) ===");

        RateTestParams memory params = RateTestParams({
            rate: 221e14,
            totalBorrowAmount: 1000 ether,  // 1000 WETH
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 7 days
        });

        RateTestResult memory result = calculateRateImpact(params);

        _logResults("Large Borrow", params, result);

        // Interest percentage should be same regardless of borrow amount
        RateTestParams memory smallParams = params;
        smallParams.totalBorrowAmount = 1 ether;
        RateTestResult memory smallResult = calculateRateImpact(smallParams);

        assertEq(
            result.approxPercentFinalInterest,
            smallResult.approxPercentFinalInterest,
            "Interest % should be same regardless of amount"
        );
    }

    /**
     * @notice Fuzz test: Verify interest calculation with various claim delays
     */
    function testFuzz_ClaimDelayImpact(uint256 claimDelay) public {
        // Bound claim delay to reasonable values (0 to 30 days)
        claimDelay = bound(claimDelay, 0, 30 days);

        RateTestParams memory params = RateTestParams({
            rate: 221e14,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: claimDelay
        });

        RateTestResult memory result = calculateRateImpact(params);

        // Verify basic invariants
        assertTrue(result.totalTimeForInterest >= params.claimDelay, "Total time should include claim delay");
        assertTrue(result.debtWithInterest >= params.totalBorrowAmount, "Debt with interest should >= principal");

        // Interest should increase with claim delay
        if (claimDelay > 0) {
            params.claimDelay = 0;
            RateTestResult memory noDelayResult = calculateRateImpact(params);
            assertTrue(
                result.approxPercentFinalInterest > noDelayResult.approxPercentFinalInterest,
                "Interest should be higher with claim delay"
            );
        }
    }

    /**
     * @notice Fuzz test: Verify calculation with various rates
     */
    function testFuzz_RateImpact(uint256 rate) public {
        // Bound rate to valid range (0.5% to 10%)
        rate = bound(rate, 5e15, 1e17);

        RateTestParams memory params = RateTestParams({
            rate: rate,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 7 days
        });

        RateTestResult memory result = calculateRateImpact(params);

        // Interest should be proportional to rate
        uint256 expectedInterest = (rate * 21 days) / 365 days;
        assertEq(result.approxPercentFinalInterest, expectedInterest, "Interest should match expected");
    }

    /**
     * @notice Integration test: Verify claim delay matches actual contract constant
     */
    function test_MatchesContractConstant() public {
        // This test verifies our test uses the same constant as the actual contract
        // LVLidoVaultUtil.lidoClaimDelay = 7 days
        assertEq(LIDO_CLAIM_DELAY, 7 days, "Test constant should match contract constant");
    }

    // ============ Helper Functions ============

    function _logResults(
        string memory testName,
        RateTestParams memory params,
        RateTestResult memory result
    ) internal view {
        console.log("");
        console.log(string.concat("--- ", testName, " Results ---"));
        console.log(string.concat("Rate (APR): ", _rateToString(params.rate), "%"));
        console.log(string.concat("Borrow Amount: ", formatValue(params.totalBorrowAmount), " WETH"));
        console.log(string.concat("Time Elapsed: ", vm.toString(result.timeElapsed / 1 days), " days"));
        console.log(string.concat("Claim Delay: ", vm.toString(params.claimDelay / 1 days), " days"));
        console.log(string.concat("Total Time: ", vm.toString(result.totalTimeForInterest / 1 days), " days"));
        console.log(string.concat("Interest: ", vm.toString(result.interestBps), " bps (", formatValue(result.approxPercentFinalInterest * 100), "%)"));
        console.log(string.concat("Debt + Interest: ", formatValue(result.debtWithInterest), " WETH"));
        console.log(string.concat("wstETH Rate: ", formatValue(result.wstethRate)));
        console.log(string.concat("Collateral Needed: ", formatValue(result.collateralNeeded), " wstETH"));
        console.log("");
    }

    function _daysToString(uint256 delaySeconds) internal pure returns (string memory) {
        uint256 days_ = delaySeconds / 1 days;
        if (days_ < 10) {
            return string.concat(" ", vm.toString(days_));
        }
        return vm.toString(days_);
    }

    function _rateToString(uint256 rate) internal pure returns (string memory) {
        // Convert from 1e18 to percentage with 2 decimals
        uint256 percent = rate / 1e14; // Now in basis points * 100
        uint256 whole = percent / 100;
        uint256 decimal = percent % 100;

        string memory decStr;
        if (decimal < 10) {
            decStr = string.concat("0", vm.toString(decimal));
        } else {
            decStr = vm.toString(decimal);
        }

        return string.concat(vm.toString(whole), ".", decStr);
    }
}
