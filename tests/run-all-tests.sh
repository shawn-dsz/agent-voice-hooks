#!/usr/bin/env bash
#
# Master test runner for Kimi Voice Hooks.
#
# Runs all test suites:
# 1. Unit tests (test_events.py)
# 2. Integration tests (test-bridge.sh)
# 3. Voice tests (test-voice.sh)
#
# Generates a summary report with aggregate results.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

# Test scripts
UNIT_TEST="${SCRIPT_DIR}/test_events.py"
INTEGRATION_TEST="${SCRIPT_DIR}/test-bridge.sh"
VOICE_TEST="${SCRIPT_DIR}/test-voice.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Test results
UNIT_RESULT=0
INTEGRATION_RESULT=0
VOICE_RESULT=0

# Counters
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# Settings
MOCK_MODE=false
VERBOSE=false
CI_MODE=false

# Logging functions
log_header() {
    echo ""
    echo "=========================================="
    echo -e "${CYAN}$1${NC}"
    echo "=========================================="
    echo ""
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${MAGENTA}>>> $1${NC}"
    echo ""
}

# Print banner
print_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║         Kimi Voice Hooks - Complete Test Suite            ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local all_ok=true
    
    # Check Python
    if ! command -v python3 &>/dev/null; then
        log_fail "Python 3 is required"
        all_ok=false
    else
        local version
        version=$(python3 --version 2>&1)
        log_info "Found: $version"
    fi
    
    # Check test files exist
    if [[ ! -f "$UNIT_TEST" ]]; then
        log_fail "Unit test not found: $UNIT_TEST"
        all_ok=false
    else
        log_info "Unit test: $UNIT_TEST"
    fi
    
    if [[ ! -f "$INTEGRATION_TEST" ]]; then
        log_fail "Integration test not found: $INTEGRATION_TEST"
        all_ok=false
    else
        log_info "Integration test: $INTEGRATION_TEST"
    fi
    
    if [[ ! -f "$VOICE_TEST" ]]; then
        log_warn "Voice test not found: $VOICE_TEST"
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
    else
        log_info "Voice test: $VOICE_TEST"
    fi
    
    if [[ "$all_ok" == false ]]; then
        echo ""
        log_fail "Prerequisites check failed"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Run unit tests
run_unit_tests() {
    log_section "Running Unit Tests"
    log_info "Test file: test_events.py"
    echo ""
    
    local start_time end_time duration
    start_time=$(date +%s)
    
    # Make script executable
    chmod +x "$UNIT_TEST"
    
    # Run tests
    if [[ "$VERBOSE" == true ]]; then
        if python3 "$UNIT_TEST" -v; then
            UNIT_RESULT=0
        else
            UNIT_RESULT=1
        fi
    else
        # Capture output but show summary
        local output
        output=$(python3 "$UNIT_TEST" 2>&1) && UNIT_RESULT=0 || UNIT_RESULT=1
        
        # Show relevant output
        echo "$output" | grep -E "^(test_|OK|FAILED|ERROR|------|Ran)" || true
        echo ""
        
        # Count tests
        local test_count
        test_count=$(echo "$output" | grep -c "^test_" 2>/dev/null || echo 0)
        log_info "Ran $test_count test cases"
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [[ $UNIT_RESULT -eq 0 ]]; then
        log_success "Unit tests passed (${duration}s)"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        log_fail "Unit tests failed (${duration}s)"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi
}

# Run integration tests
run_integration_tests() {
    log_section "Running Integration Tests"
    log_info "Test file: test-bridge.sh"
    echo ""
    
    local start_time end_time duration
    start_time=$(date +%s)
    
    # Make script executable
    chmod +x "$INTEGRATION_TEST"
    
    # Run tests
    local extra_args=""
    if [[ "$MOCK_MODE" == true ]]; then
        extra_args="--quick"
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        if bash "$INTEGRATION_TEST" $extra_args; then
            INTEGRATION_RESULT=0
        else
            INTEGRATION_RESULT=1
        fi
    else
        # Run and capture result, show summary only
        if bash "$INTEGRATION_TEST" $extra_args 2>&1 | tail -20; then
            INTEGRATION_RESULT=0
        else
            INTEGRATION_RESULT=1
        fi
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [[ $INTEGRATION_RESULT -eq 0 ]]; then
        log_success "Integration tests passed (${duration}s)"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        log_fail "Integration tests failed (${duration}s)"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi
}

# Run voice tests
run_voice_tests() {
    if [[ ! -f "$VOICE_TEST" ]]; then
        log_warn "Skipping voice tests (file not found)"
        return 0
    fi
    
    log_section "Running Voice Tests"
    log_info "Test file: test-voice.sh"
    echo ""
    
    local start_time end_time duration
    start_time=$(date +%s)
    
    # Make script executable
    chmod +x "$VOICE_TEST"
    
    # Run tests
    local extra_args=""
    if [[ "$MOCK_MODE" == true ]] || [[ "$CI_MODE" == true ]]; then
        extra_args="--mock"
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        if bash "$VOICE_TEST" $extra_args; then
            VOICE_RESULT=0
        else
            VOICE_RESULT=1
        fi
    else
        # Run and capture result, show summary only
        if bash "$VOICE_TEST" $extra_args 2>&1 | tail -20; then
            VOICE_RESULT=0
        else
            VOICE_RESULT=1
        fi
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [[ $VOICE_RESULT -eq 0 ]]; then
        log_success "Voice tests passed (${duration}s)"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        log_fail "Voice tests failed (${duration}s)"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi
}

# Print detailed report
print_report() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                      TEST REPORT                          ║"
    echo "╠═══════════════════════════════════════════════════════════╣"
    
    # Unit tests
    if [[ $UNIT_RESULT -eq 0 ]]; then
        echo "║  Unit Tests:        ${GREEN}✓ PASSED${NC}                              ║"
    else
        echo "║  Unit Tests:        ${RED}✗ FAILED${NC}                              ║"
    fi
    
    # Integration tests
    if [[ $INTEGRATION_RESULT -eq 0 ]]; then
        echo "║  Integration Tests: ${GREEN}✓ PASSED${NC}                              ║"
    else
        echo "║  Integration Tests: ${RED}✗ FAILED${NC}                              ║"
    fi
    
    # Voice tests
    if [[ -f "$VOICE_TEST" ]]; then
        if [[ $VOICE_RESULT -eq 0 ]]; then
            echo "║  Voice Tests:       ${GREEN}✓ PASSED${NC}                              ║"
        else
            echo "║  Voice Tests:       ${RED}✗ FAILED${NC}                              ║"
        fi
    else
        echo "║  Voice Tests:       ${YELLOW}⊘ SKIPPED${NC}                             ║"
    fi
    
    echo "╠═══════════════════════════════════════════════════════════╣"
    
    # Summary
    local total_tests=$((TOTAL_PASSED + TOTAL_FAILED + TOTAL_SKIPPED))
    
    echo -e "║  Total Suites:      $total_tests                                    ║"
    echo -e "║  Passed:            ${GREEN}$TOTAL_PASSED${NC}                                    ║"
    echo -e "║  Failed:            ${RED}$TOTAL_FAILED${NC}                                    ║"
    
    if [[ $TOTAL_SKIPPED -gt 0 ]]; then
        echo -e "║  Skipped:           ${YELLOW}$TOTAL_SKIPPED${NC}                                    ║"
    fi
    
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Final result
    if [[ $TOTAL_FAILED -eq 0 ]]; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}              ALL TESTS PASSED SUCCESSFULLY!               ${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}                    SOME TESTS FAILED                      ${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        return 1
    fi
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Master test runner for Kimi Voice Hooks.

OPTIONS:
    -h, --help          Show this help message
    -q, --quick         Quick mode (skip timing-dependent tests)
    -v, --verbose       Verbose output
    --ci                CI mode (mock all external dependencies)
    --unit-only         Run only unit tests
    --integration-only  Run only integration tests
    --voice-only        Run only voice tests

EXAMPLES:
    $0                  Run all tests
    $0 --quick          Run quick tests only
    $0 --ci             Run in CI mode (mocked)
    $0 --unit-only      Run only unit tests
EOF
}

# Main function
main() {
    local unit_only=false
    local integration_only=false
    local voice_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                exit 0
                ;;
            -q|--quick)
                MOCK_MODE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --ci)
                CI_MODE=true
                MOCK_MODE=true
                shift
                ;;
            --unit-only)
                unit_only=true
                shift
                ;;
            --integration-only)
                integration_only=true
                shift
                ;;
            --voice-only)
                voice_only=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    print_banner
    
    # Check prerequisites
    check_prerequisites
    
    # Determine which tests to run
    local run_unit=true
    local run_integration=true
    local run_voice=true
    
    if [[ "$unit_only" == true ]]; then
        run_integration=false
        run_voice=false
    elif [[ "$integration_only" == true ]]; then
        run_unit=false
        run_voice=false
    elif [[ "$voice_only" == true ]]; then
        run_unit=false
        run_integration=false
    fi
    
    # Run tests
    if [[ "$run_unit" == true ]]; then
        run_unit_tests
    fi
    
    if [[ "$run_integration" == true ]]; then
        run_integration_tests
    fi
    
    if [[ "$run_voice" == true ]]; then
        run_voice_tests
    fi
    
    # Print final report
    print_report
}

# Run main
main "$@"
