#!/bin/bash

# Morpho Flash Loan Test Runner Script
# Usage: ./test/run-morpho-tests.sh [test_name] [verbosity]

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo -e "${YELLOW}Please create a .env file with ETH_RPC_URL${NC}"
    echo "Example: ETH_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/YOUR_API_KEY"
    exit 1
fi

# Load environment variables
source .env

if [ -z "$ETH_RPC_URL" ]; then
    echo -e "${RED}Error: ETH_RPC_URL not set in .env${NC}"
    exit 1
fi

# Set verbosity (default to -vvv)
VERBOSITY=${2:--vvv}

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Morpho Flash Loan Test Suite Runner     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Function to run a specific test
run_test() {
    local test_name=$1
    echo -e "${GREEN}Running: ${test_name}${NC}"
    echo "----------------------------------------"
    forge test --match-test $test_name $VERBOSITY --fork-url $ETH_RPC_URL
    echo ""
}

# Function to run all Morpho tests
run_all_tests() {
    echo -e "${GREEN}Running all Morpho Flash Loan tests...${NC}"
    echo "----------------------------------------"
    forge test --match-contract MorphoFlashLoanTests $VERBOSITY --fork-url $ETH_RPC_URL
}

# Function to run with gas report
run_gas_report() {
    echo -e "${GREEN}Running tests with gas report...${NC}"
    echo "----------------------------------------"
    forge test --match-contract MorphoFlashLoanTests --gas-report --fork-url $ETH_RPC_URL
}

# Main script logic
case "$1" in
    "basic")
        run_test "testMorphoFlashLoanBasic"
        ;;
    "multiple")
        run_test "testMorphoFlashLoanMultipleParticipants"
        ;;
    "callback")
        run_test "testMorphoFlashLoanCallbackValidation"
        ;;
    "repayment")
        run_test "testMorphoFlashLoanRepaymentFlow"
        ;;
    "conversion")
        run_test "testWethToWstethConversion"
        ;;
    "minimum")
        run_test "testMorphoFlashLoanMinimumAmounts"
        ;;
    "insufficient")
        run_test "testMorphoFlashLoanInsufficientCollateralLender"
        ;;
    "gas")
        run_gas_report
        ;;
    "all"|"")
        run_all_tests
        ;;
    "help"|"-h"|"--help")
        echo -e "${BLUE}Usage:${NC} ./test/run-morpho-tests.sh [test_name] [verbosity]"
        echo ""
        echo -e "${BLUE}Test names:${NC}"
        echo "  all          - Run all Morpho tests (default)"
        echo "  basic        - Basic flash loan test"
        echo "  multiple     - Multiple participants test"
        echo "  callback     - Callback validation test"
        echo "  repayment    - Repayment flow test"
        echo "  conversion   - WETH to WSTETH conversion test"
        echo "  minimum      - Minimum amounts test"
        echo "  insufficient - Insufficient collateral lender test"
        echo "  gas          - Run with gas report"
        echo ""
        echo -e "${BLUE}Verbosity levels:${NC}"
        echo "  -v    - Basic verbosity"
        echo "  -vv   - More verbosity"
        echo "  -vvv  - Even more verbosity (default)"
        echo "  -vvvv - Maximum verbosity with traces"
        echo ""
        echo -e "${BLUE}Examples:${NC}"
        echo "  ./test/run-morpho-tests.sh"
        echo "  ./test/run-morpho-tests.sh basic"
        echo "  ./test/run-morpho-tests.sh basic -vvvv"
        echo "  ./test/run-morpho-tests.sh gas"
        ;;
    *)
        echo -e "${RED}Unknown test: $1${NC}"
        echo "Run './test/run-morpho-tests.sh help' for usage information"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Tests Complete                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"

