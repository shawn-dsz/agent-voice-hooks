#!/usr/bin/env bash
#
# Test script for voice output abstraction
# Tests each TTS backend and provides diagnostic output
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="${SCRIPT_DIR}/../bridge"
VOICE_PY="${BRIDGE_DIR}/voice.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++)) || true
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++)) || true
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if Python is available
check_python() {
    log_info "Checking Python version..."
    
    if ! command -v python3 &>/dev/null; then
        log_fail "Python 3 is not installed"
        return 1
    fi
    
    local version
    version=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1,2)
    local major
    major=$(echo "$version" | cut -d'.' -f1)
    local minor
    minor=$(echo "$version" | cut -d'.' -f2)
    
    if [[ "$major" -lt 3 ]] || [[ "$major" -eq 3 && "$minor" -lt 10 ]]; then
        log_fail "Python 3.10+ required, found $version"
        return 1
    fi
    
    log_success "Python $version is available"
    return 0
}

# Check if voice.py exists
check_voice_py() {
    log_info "Checking voice.py module..."
    
    if [[ ! -f "$VOICE_PY" ]]; then
        log_fail "voice.py not found at $VOICE_PY"
        return 1
    fi
    
    log_success "voice.py found"
    return 0
}

# Test Python syntax
test_syntax() {
    log_info "Checking Python syntax..."
    
    if python3 -m py_compile "$VOICE_PY" 2>&1; then
        log_success "Python syntax is valid"
        return 0
    else
        log_fail "Python syntax errors detected"
        return 1
    fi
}

# Get backend info from voice.py
get_backend_info() {
    python3 "$VOICE_PY" --info 2>/dev/null || echo '{}'
}

# Test backend detection
test_backend_detection() {
    log_info "Testing backend auto-detection..."
    
    local info
    info=$(get_backend_info)
    local selected
    selected=$(echo "$info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('selected','unknown'))")
    
    log_info "Auto-detected backend: $selected"
    
    case "$selected" in
        voicemode)
            log_success "voicemode detected as primary backend"
            ;;
        say)
            log_success "say detected as primary backend"
            ;;
        silent)
            log_warn "No TTS backend found, using silent mode"
            ;;
        *)
            log_fail "Unknown backend: $selected"
            return 1
            ;;
    esac
    
    return 0
}

# Test voicemode backend
test_voicemode() {
    log_info "Testing voicemode backend..."
    
    if ! command -v voicemode &>/dev/null; then
        log_warn "voicemode not installed, skipping"
        return 0
    fi
    
    log_info "voicemode is installed"
    
    # Check if we're in CI/mock mode
    if [[ "${VOICE_TEST_MOCK:-}" == "1" ]]; then
        log_info "MOCK mode: Simulating voicemode success"
        log_success "voicemode backend test (mocked)"
        return 0
    fi
    
    # Test actual voice output (very short message)
    if timeout 10 python3 "$VOICE_PY" --backend voicemode --voice af_sky "Testing" 2>/dev/null; then
        log_success "voicemode backend works"
        return 0
    else
        log_fail "voicemode backend failed"
        return 1
    fi
}

# Test say backend
test_say() {
    log_info "Testing say backend..."
    
    if ! command -v say &>/dev/null; then
        log_warn "say not available (not macOS?), skipping"
        return 0
    fi
    
    log_info "say is available"
    
    # Check if we're in CI/mock mode
    if [[ "${VOICE_TEST_MOCK:-}" == "1" ]]; then
        log_info "MOCK mode: Simulating say success"
        log_success "say backend test (mocked)"
        return 0
    fi
    
    # Test actual voice output (very short message)
    if timeout 10 python3 "$VOICE_PY" --backend say --voice Samantha "Testing" 2>/dev/null; then
        log_success "say backend works"
        return 0
    else
        log_fail "say backend failed"
        return 1
    fi
}

# Test silent backend
test_silent() {
    log_info "Testing silent backend..."
    
    local output
    output=$(python3 "$VOICE_PY" --backend silent "Silent test message" 2>&1)
    
    if echo "$output" | grep -q "Silent test message"; then
        log_success "silent backend works"
        return 0
    else
        log_fail "silent backend did not produce expected output"
        echo "Output was: $output"
        return 1
    fi
}

# Test error handling
test_error_handling() {
    log_info "Testing error handling..."
    
    # Test with empty message (should not crash)
    if python3 "$VOICE_PY" "" 2>/dev/null; then
        log_success "Empty message handled gracefully"
    else
        log_fail "Empty message caused error"
        return 1
    fi
    
    # Test with very long message
    local long_msg
    long_msg=$(python3 -c "print('word ' * 100)")
    if timeout 5 python3 "$VOICE_PY" --backend silent "$long_msg" 2>/dev/null; then
        log_success "Long message handled gracefully"
    else
        log_fail "Long message caused error"
        return 1
    fi
    
    return 0
}

# Test Python module import
test_module_import() {
    log_info "Testing Python module import..."
    
    if python3 -c "
import sys
sys.path.insert(0, '$BRIDGE_DIR')
import voice
print('TTSBackend:', voice.TTSBackend)
print('VoiceConfig:', voice.VoiceConfig)
print('speak:', voice.speak)
print('detect_backend:', voice.detect_backend)
" 2>/dev/null; then
        log_success "Module imports correctly"
        return 0
    else
        log_fail "Module import failed"
        return 1
    fi
}

# Run diagnostics
run_diagnostics() {
    echo ""
    echo "=========================================="
    echo "         Voice Output Diagnostics         "
    echo "=========================================="
    echo ""
    
    log_info "Running system diagnostics..."
    
    # Check OS
    log_info "Operating System: $(uname -s)"
    
    # Check Python
    log_info "Python: $(python3 --version 2>&1)"
    
    # Show backend info
    log_info "Backend Information:"
    get_backend_info | python3 -m json.tool 2>/dev/null || echo "  (could not parse)"
    
    # Check for voicemode
    if command -v voicemode &>/dev/null; then
        log_info "voicemode: $(voicemode --version 2>&1 || echo 'version unknown')"
    else
        log_warn "voicemode: not installed"
    fi
    
    # Check for say
    if command -v say &>/dev/null; then
        log_info "say: available"
        # List available voices
        log_info "Available voices (first 10):"
        say -v '?' 2>/dev/null | head -10 | while read -r line; do
            echo "  - $line"
        done
    else
        log_warn "say: not available"
    fi
    
    echo ""
}

# Mock mode setup for CI
setup_mock() {
    if [[ "${VOICE_TEST_MOCK:-}" != "1" ]]; then
        return 0
    fi
    
    log_info "Setting up mock environment for CI/testing..."
    
    # Create mock voicemode command
    MOCK_DIR=$(mktemp -d)
    cat > "$MOCK_DIR/voicemode" << 'EOF'
#!/bin/bash
# Mock voicemode for testing

if [[ "$1" == "--version" ]]; then
    echo "voicemode 0.1.0 (mock)"
    exit 0
fi

if [[ "$1" == "converse" ]]; then
    # Parse arguments to find message
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--message)
                echo "[MOCK voicemode] Would speak: $2" >&2
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    exit 0
fi

echo "[MOCK voicemode] Unknown command: $1" >&2
exit 1
EOF
    chmod +x "$MOCK_DIR/voicemode"
    
    # Add to PATH
    export PATH="$MOCK_DIR:$PATH"
    
    log_info "Mock voicemode created at $MOCK_DIR/voicemode"
}

# Cleanup mock
cleanup_mock() {
    if [[ -n "${MOCK_DIR:-}" ]] && [[ -d "$MOCK_DIR" ]]; then
        rm -rf "$MOCK_DIR"
    fi
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test voice output abstraction for Kimi Voice Hooks.

OPTIONS:
    -h, --help          Show this help message
    -d, --diagnostics   Run diagnostics only (no tests)
    -m, --mock          Enable mock mode for CI/testing
    -q, --quick         Quick test (skip actual audio playback)

ENVIRONMENT:
    VOICE_TEST_MOCK=1   Same as --mock flag

EXAMPLES:
    $0                  Run all tests
    $0 --diagnostics    Show system diagnostics
    $0 --mock           Run with mocked TTS backends
EOF
}

# Main function
main() {
    local diagnostics_only=false
    local quick_mode=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                exit 0
                ;;
            -d|--diagnostics)
                diagnostics_only=true
                shift
                ;;
            -m|--mock)
                export VOICE_TEST_MOCK=1
                shift
                ;;
            -q|--quick)
                quick_mode=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    echo "=========================================="
    echo "     Voice Output Abstraction Tests       "
    echo "=========================================="
    echo ""
    
    # Setup mock if needed
    setup_mock
    trap cleanup_mock EXIT
    
    # Run diagnostics first
    if [[ "$diagnostics_only" == true ]]; then
        run_diagnostics
        exit 0
    fi
    
    run_diagnostics
    
    echo "Running tests..."
    echo ""
    
    # Basic checks
    check_python
    check_voice_py
    test_syntax
    test_module_import
    
    # Backend tests
    test_backend_detection
    test_silent
    
    if [[ "$quick_mode" == false ]]; then
        test_voicemode
        test_say
    else
        log_info "Quick mode: skipping audio playback tests"
    fi
    
    # Error handling tests
    test_error_handling
    
    # Summary
    echo ""
    echo "=========================================="
    echo "              Test Summary                "
    echo "=========================================="
    echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

# Run main
main "$@"
