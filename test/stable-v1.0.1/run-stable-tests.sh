#!/bin/bash
# Run all stable-v1.0.1 regression tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║          STABLE v1.0.1 REGRESSION TEST SUITE                 ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check for RPC URL
if [ -z "$ETH_RPC_URL" ]; then
    echo -e "${RED}Error: ETH_RPC_URL environment variable not set${NC}"
    echo "Usage: ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY ./run-stable-tests.sh"
    exit 1
fi

echo -e "${GREEN}Using RPC: ${ETH_RPC_URL:0:50}...${NC}"
echo ""

# Test contracts in order
TESTS=(
    "ReentrancyFixTest"
    "RateFallbackTest"
    "PublicPerformTaskTest"
    "QueueArchitectureTest"
    "CollateralAutomationTest"
    "AutomationsIntegrationTest"
)

PASSED=0
FAILED=0

for TEST in "${TESTS[@]}"; do
    echo -e "${YELLOW}Running: $TEST${NC}"
    if forge test --match-contract "$TEST" --fork-url "$ETH_RPC_URL" -vv; then
        echo -e "${GREEN}✓ $TEST PASSED${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ $TEST FAILED${NC}"
        ((FAILED++))
    fi
    echo ""
done

# Also run existing tests
echo -e "${YELLOW}Running existing test suites...${NC}"

EXISTING_TESTS=(
    "GetterFunctionsTest"
    "MorphoFlashLoanTests"
    "E2EEpochSimulation"
)

for TEST in "${EXISTING_TESTS[@]}"; do
    echo -e "${YELLOW}Running: $TEST${NC}"
    if forge test --match-contract "$TEST" --fork-url "$ETH_RPC_URL" -vv 2>/dev/null; then
        echo -e "${GREEN}✓ $TEST PASSED${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ $TEST FAILED (or skipped)${NC}"
        ((FAILED++))
    fi
    echo ""
done

# Summary
echo -e "${YELLOW}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}PASSED: $PASSED${NC}"
echo -e "${RED}FAILED: $FAILED${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════════════════════${NC}"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
