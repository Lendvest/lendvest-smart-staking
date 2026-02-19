#!/bin/bash

# End-to-End Test Runner for LVLidoVault
# This script provides convenient commands to run the E2E test suite

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please create a .env file with MAINNET_RPC_URL"
    exit 1
fi

# Load environment variables
source .env

# Check if MAINNET_RPC_URL is set
if [ -z "$MAINNET_RPC_URL" ]; then
    echo -e "${RED}Error: MAINNET_RPC_URL not set in .env${NC}"
    exit 1
fi

echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}  LVLidoVault E2E Test Suite${NC}"
echo -e "${GREEN}==================================${NC}"
echo ""

# Parse command line arguments
VERBOSITY="-vvv"
TEST_FILTER=""
GAS_REPORT=""
COVERAGE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -v)
            VERBOSITY="-v"
            shift
            ;;
        -vv)
            VERBOSITY="-vv"
            shift
            ;;
        -vvv)
            VERBOSITY="-vvv"
            shift
            ;;
        -vvvv)
            VERBOSITY="-vvvv"
            shift
            ;;
        --test)
            TEST_FILTER="--match-test $2"
            shift 2
            ;;
        --gas)
            GAS_REPORT="--gas-report"
            shift
            ;;
        --coverage)
            COVERAGE="true"
            shift
            ;;
        --help)
            echo "Usage: ./test/run-e2e-tests.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -v, -vv, -vvv, -vvvv    Set verbosity level (default: -vvv)"
            echo "  --test <name>           Run specific test"
            echo "  --gas                   Show gas report"
            echo "  --coverage              Generate coverage report"
            echo "  --help                  Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./test/run-e2e-tests.sh"
            echo "  ./test/run-e2e-tests.sh --test test_FullEpochLifecycle -vvvv"
            echo "  ./test/run-e2e-tests.sh --gas"
            echo "  ./test/run-e2e-tests.sh --coverage"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run tests based on options
if [ "$COVERAGE" = "true" ]; then
    echo -e "${YELLOW}Generating coverage report...${NC}"
    forge coverage --match-path test/E2E.t.sol --fork-url $MAINNET_RPC_URL
elif [ -n "$TEST_FILTER" ]; then
    echo -e "${YELLOW}Running specific test: $TEST_FILTER${NC}"
    forge test $TEST_FILTER $VERBOSITY $GAS_REPORT --fork-url $MAINNET_RPC_URL
else
    echo -e "${YELLOW}Running all E2E tests...${NC}"
    forge test --match-path test/E2E.t.sol $VERBOSITY $GAS_REPORT --fork-url $MAINNET_RPC_URL
fi

# Check exit code
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi

