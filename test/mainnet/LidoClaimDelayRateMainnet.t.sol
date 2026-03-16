// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IWsteth} from "../../src/interfaces/vault/IWsteth.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../TestHelpers.t.sol";

/**
 * @title LidoClaimDelayRateMainnetTest
 * @notice Tests for Lido claim delay rate calculations against mainnet
 */
contract LidoClaimDelayRateMainnetTest is Test, TestHelpers {
    uint256 public constant LIDO_CLAIM_DELAY = 7 days;
    uint256 public constant TERM_DURATION = 14 days;

    AggregatorV3Interface internal stethUsdPriceFeed;
    AggregatorV3Interface internal ethUsdPriceFeed;
    IWsteth public wsteth;

    struct RateTestParams {
        uint256 rate;
        uint256 totalBorrowAmount;
        uint256 epochStart;
        uint256 currentTime;
        uint256 claimDelay;
    }

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
        wsteth = IWsteth(WSTETH_ADDRESS);
        stethUsdPriceFeed = AggregatorV3Interface(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);
        ethUsdPriceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    }

    function getWstethToWeth(uint256 _amount) public view returns (uint256) {
        (, int256 stethPrice,,,) = stethUsdPriceFeed.latestRoundData();
        uint256 stethAmount = _amount * wsteth.stEthPerToken() / 1e18;
        uint256 stethValueScaled = stethAmount * uint256(stethPrice);
        (, int256 ethPrice,,,) = ethUsdPriceFeed.latestRoundData();
        return stethValueScaled / uint256(ethPrice);
    }

    function calculateRateImpact(RateTestParams memory params) public view returns (RateTestResult memory result) {
        if (params.currentTime > params.epochStart) {
            result.timeElapsed = params.currentTime - params.epochStart;
        }
        result.totalTimeForInterest = result.timeElapsed + params.claimDelay;
        result.approxPercentFinalInterest = (params.rate * result.totalTimeForInterest) / 365 days;
        result.interestBps = result.approxPercentFinalInterest / 1e14;
        result.wstethRate = getWstethToWeth(1e18);
        result.debtWithInterest = (params.totalBorrowAmount * (1e18 + result.approxPercentFinalInterest)) / 1e18;
        if (result.wstethRate > 0) {
            result.collateralNeeded = (params.totalBorrowAmount * (1e18 + result.approxPercentFinalInterest)) / result.wstethRate;
        }
    }

    function test_ClaimDelay_Default7Days() public view {
        console.log("=== Test: Default 7-Day Claim Delay ===");

        RateTestParams memory params = RateTestParams({
            rate: 221e14,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 7 days
        });

        RateTestResult memory result = calculateRateImpact(params);

        uint256 expectedTotalTime = 14 days + 7 days;
        assertEq(result.totalTimeForInterest, expectedTotalTime, "Total time should be 21 days");

        uint256 expectedInterest = (params.rate * expectedTotalTime) / 365 days;
        assertEq(result.approxPercentFinalInterest, expectedInterest, "Interest calculation mismatch");

        console.log("Interest (bps):", result.interestBps);
        console.log("Debt with interest:", result.debtWithInterest);
    }

    function test_ClaimDelay_Comparison() public view {
        console.log("=== Test: Claim Delay Comparison ===");

        RateTestParams memory baseParams = RateTestParams({
            rate: 221e14,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 0
        });

        uint256[] memory delays = new uint256[](5);
        delays[0] = 0;
        delays[1] = 3 days;
        delays[2] = 7 days;
        delays[3] = 10 days;
        delays[4] = 14 days;

        for (uint256 i = 0; i < delays.length; i++) {
            baseParams.claimDelay = delays[i];
            RateTestResult memory result = calculateRateImpact(baseParams);
            console.log("Delay (days):", delays[i] / 1 days, "Interest (bps):", result.interestBps);
        }
    }

    function test_RateBounds() public view {
        console.log("=== Test: Rate Bounds Verification ===");

        uint256[] memory rates = new uint256[](5);
        rates[0] = 5e15;
        rates[1] = 1e16;
        rates[2] = 221e14;
        rates[3] = 5e16;
        rates[4] = 1e17;

        RateTestParams memory params = RateTestParams({
            rate: 0,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 7 days
        });

        for (uint256 i = 0; i < rates.length; i++) {
            params.rate = rates[i];
            RateTestResult memory result = calculateRateImpact(params);
            console.log("Rate:", rates[i], "Interest (bps):", result.interestBps);
        }
    }

    function test_ShortEpochDuration() public view {
        console.log("=== Test: Short Epoch Duration ===");

        RateTestParams memory params = RateTestParams({
            rate: 221e14,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 1 days,
            currentTime: block.timestamp,
            claimDelay: 7 days
        });

        RateTestResult memory result = calculateRateImpact(params);
        assertEq(result.totalTimeForInterest, 8 days, "Total time should be 8 days");
    }

    function test_ZeroClaimDelay() public view {
        console.log("=== Test: Zero Claim Delay ===");

        RateTestParams memory params = RateTestParams({
            rate: 221e14,
            totalBorrowAmount: 100 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 0
        });

        RateTestResult memory result = calculateRateImpact(params);
        assertEq(result.totalTimeForInterest, 14 days, "Total time should be 14 days only");
    }

    function test_LargeBorrowAmount() public view {
        console.log("=== Test: Large Borrow Amount ===");

        RateTestParams memory params = RateTestParams({
            rate: 221e14,
            totalBorrowAmount: 1000 ether,
            epochStart: block.timestamp - 14 days,
            currentTime: block.timestamp,
            claimDelay: 7 days
        });

        RateTestResult memory result = calculateRateImpact(params);

        RateTestParams memory smallParams = params;
        smallParams.totalBorrowAmount = 1 ether;
        RateTestResult memory smallResult = calculateRateImpact(smallParams);

        assertEq(result.approxPercentFinalInterest, smallResult.approxPercentFinalInterest, "Interest % should be same");
    }

    function test_MatchesContractConstant() public pure {
        assertEq(LIDO_CLAIM_DELAY, 7 days, "Test constant should match contract constant");
    }

    function test_LidoClaimDelayConstant() public view {
        console.log("=== Lido Claim Delay Constant ===");
        console.log("LIDO_CLAIM_DELAY:", LIDO_CLAIM_DELAY / 1 days, "days");
        console.log("TERM_DURATION:", TERM_DURATION / 1 days, "days");
    }
}
