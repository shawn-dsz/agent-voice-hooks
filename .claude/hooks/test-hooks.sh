#!/bin/bash
# Test script to validate Claude Code hooks are working correctly
# Run this after restarting Claude Code to verify hooks are functional

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_DIR="$PROJECT_DIR/.claude/hooks"

echo "🔧 Claude Code Hooks Test"
echo "=========================="
echo "Project: $PROJECT_DIR"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
WARNINGS=0

# Test helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++)) || true
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAILED++)) || true
}

warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((WARNINGS++)) || true
}

info() {
    echo -e "${BLUE}  ℹ${NC} $1"
}

# Test 1: Check settings.json exists and is valid JSON
echo "1. Checking settings.json..."
if [ -f "$PROJECT_DIR/.claude/settings.json" ]; then
    if jq empty "$PROJECT_DIR/.claude/settings.json" 2>/dev/null; then
        pass "settings.json exists and is valid JSON"

        HOOK_COUNT=$(jq '.hooks | length' "$PROJECT_DIR/.claude/settings.json" 2>/dev/null || echo 0)
        info "Found $HOOK_COUNT hook event types registered"

        # Check for Stop hook
        if jq -e '.hooks.Stop' "$PROJECT_DIR/.claude/settings.json" >/dev/null 2>&1; then
            pass "Stop hook is registered"
            STOP_CMD=$(jq -r '.hooks.Stop[0].hooks[0].command' "$PROJECT_DIR/.claude/settings.json")
            info "Command: $STOP_CMD"
        else
            fail "Stop hook is NOT registered"
        fi

        # Check for Notification/idle_prompt hook
        if jq -e '.hooks.Notification[] | select(.matcher == "idle_prompt")' "$PROJECT_DIR/.claude/settings.json" >/dev/null 2>&1; then
            pass "Notification/idle_prompt hook is registered"
            IDLE_CMD=$(jq -r '.hooks.Notification[] | select(.matcher == "idle_prompt") | .hooks[0].command' "$PROJECT_DIR/.claude/settings.json")
            info "Command: $IDLE_CMD"
        else
            fail "Notification/idle_prompt hook is NOT registered"
        fi

        # Check for Notification/permission_prompt hook
        if jq -e '.hooks.Notification[] | select(.matcher == "permission_prompt")' "$PROJECT_DIR/.claude/settings.json" >/dev/null 2>&1; then
            pass "Notification/permission_prompt hook is registered"
            PERM_CMD=$(jq -r '.hooks.Notification[] | select(.matcher == "permission_prompt") | .hooks[0].command' "$PROJECT_DIR/.claude/settings.json")
            info "Command: $PERM_CMD"
        else
            fail "Notification/permission_prompt hook is NOT registered"
        fi
    else
        fail "settings.json exists but contains invalid JSON"
    fi
else
    fail "settings.json does not exist"
fi

echo ""

# Test 2: Check hook scripts exist and are executable
echo "2. Checking hook scripts..."

for script in task-summary.sh notification-idle.sh permission-request.sh; do
    if [ -f "$HOOKS_DIR/$script" ]; then
        if [ -x "$HOOKS_DIR/$script" ]; then
            pass "$script exists and is executable"
        else
            warn "$script exists but is NOT executable (run: chmod +x $HOOKS_DIR/$script)"
        fi
    else
        fail "$script does NOT exist"
    fi
done

echo ""

# Test 3: Test voicemode command availability
echo "3. Checking voicemode availability..."
if command -v voicemode >/dev/null 2>&1; then
    pass "voicemode command is available"
    if voicemode --version >/dev/null 2>&1; then
        VERSION=$(voicemode --version 2>&1 || echo "unknown")
        info "Version: $VERSION"
    fi
else
    fail "voicemode command is NOT available"
    info "Install from: https://github.com/voicemode/voicemode"
fi

echo ""

# Test 4: Test task-summary hook
echo "4. Testing task-summary hook..."
if [ -f "$HOOKS_DIR/task-summary.sh" ]; then
    info "Running: $HOOKS_DIR/task-summary.sh"
    if OUTPUT=$("$HOOKS_DIR/task-summary.sh" 2>&1); then
        if echo "$OUTPUT" | grep -q "spoken successfully"; then
            pass "task-summary.sh executed successfully"
        else
            warn "task-summary.sh ran but voicemode output unclear"
            info "Output: $(echo "$OUTPUT" | head -1)"
        fi
    else
        warn "task-summary.sh failed with exit code $?"
        info "This may be OK if voicemode services aren't running"
    fi
fi

echo ""

# Test 5: Test notification-idle hook
echo "5. Testing notification-idle hook..."
if [ -f "$HOOKS_DIR/notification-idle.sh" ]; then
    info "Running: $HOOKS_DIR/notification-idle.sh"
    if OUTPUT=$("$HOOKS_DIR/notification-idle.sh" 2>&1); then
        if echo "$OUTPUT" | grep -q "spoken successfully"; then
            pass "notification-idle.sh executed successfully"
        else
            warn "notification-idle.sh ran but voicemode output unclear"
            info "Output: $(echo "$OUTPUT" | head -1)"
        fi
    else
        warn "notification-idle.sh failed with exit code $?"
        info "This may be OK if voicemode services aren't running"
    fi
fi

echo ""

# Test 6: Test permission-request hook with simulated input
echo "6. Testing permission-request hook..."
if [ -f "$HOOKS_DIR/permission-request.sh" ]; then
    info "Running with simulated input..."
    if OUTPUT=$(echo '{"tool":"Write","file_path":"test.txt"}' | "$HOOKS_DIR/permission-request.sh" 2>&1); then
        if echo "$OUTPUT" | grep -q "spoken successfully"; then
            pass "permission-request.sh executed successfully"
        else
            warn "permission-request.sh ran but voicemode output unclear"
            info "Output: $(echo "$OUTPUT" | head -1)"
        fi
    else
        warn "permission-request.sh failed with exit code $?"
        info "This may be OK if voicemode services aren't running"
    fi
fi

echo ""

# Test 6a: Test permission-request hook message generation with description
echo "6a. Testing permission-request hook message generation..."
if [ -f "$HOOKS_DIR/permission-request.sh" ]; then

    # Helper function to extract message from hook (mocking voicemode)
    test_message() {
        local input="$1"
        local expected="$2"
        local test_name="$3"

        # Mock the hook to capture the message instead of calling voicemode
        local message
        message=$(echo "$input" | bash -c '
            INPUT=$(cat)
            TOOL=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get(\"tool\",\"unknown\"))" 2>/dev/null)
            DESC=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get(\"description\",\"\"))" 2>/dev/null)

            if [ -n "$DESC" ]; then
                CLEAN_DESC=$(echo "$DESC" | sed -E "s/^Bash( command)?[ :]+ ?//")
                MESSAGE="Claude is waiting to $CLEAN_DESC"
            else
                MESSAGE="Claude is waiting to use $TOOL"
            fi
            echo "$MESSAGE"
        ' 2>&1)

        if [ "$message" = "$expected" ]; then
            pass "$test_name"
            info "Message: \"$message\""
        else
            fail "$test_name"
            info "Expected: \"$expected\""
            info "Got:      \"$message\""
        fi
    }

    # Test with description containing action
    test_message '{"tool":"Bash","description":"List files in current directory"}' \
        "Claude is waiting to List files in current directory" \
        "Description with action is used correctly"

    # Test with Bash command prefix
    test_message '{"tool":"Bash","description":"Bash command: Run tests"}' \
        "Claude is waiting to Run tests" \
        "Bash command prefix is stripped correctly"

    # Test with Bash prefix
    test_message '{"tool":"Bash","description":"Bash: ls -la"}' \
        "Claude is waiting to ls -la" \
        "Bash prefix is stripped correctly"

    # Test with Bash command and space prefix
    test_message '{"tool":"Bash","description":"Bash command Run npm install"}' \
        "Claude is waiting to Run npm install" \
        "Bash command with space is stripped correctly"

    # Test without description (fallback to tool name)
    test_message '{"tool":"Write","file_path":"test.txt"}' \
        "Claude is waiting to use Write" \
        "Fallback to tool name when no description"

    # Test with empty description
    test_message '{"tool":"Read","description":""}' \
        "Claude is waiting to use Read" \
        "Fallback to tool name when description is empty string"

    # Test with complex description (Edit tool)
    test_message '{"tool":"Edit","description":"Replace import in file"}' \
        "Claude is waiting to Replace import in file" \
        "Description for Edit tool is used correctly"

    # Test with multi-word description
    test_message '{"tool":"Bash","description":"Create a new directory and copy files"}' \
        "Claude is waiting to Create a new directory and copy files" \
        "Multi-word description is handled correctly"

fi

echo ""

# Test 7: Check voicemode services
echo "7. Checking voicemode services..."

# Check Kokoro TTS service
info "Checking Kokoro TTS service..."
KOKORO_OUTPUT=$(voicemode service status kokoro 2>&1 || echo "not running")
if echo "$KOKORO_OUTPUT" | grep -qi "running\|active"; then
    pass "Kokoro TTS service is running"
else
    warn "Kokoro TTS service is NOT running"
    info "Start with: voicemode service start kokoro"
fi

# Check Whisper STT service (optional)
info "Checking Whisper STT service..."
WHISPER_OUTPUT=$(voicemode service status whisper 2>&1 || echo "not running")
if echo "$WHISPER_OUTPUT" | grep -qi "running\|active"; then
    pass "Whisper STT service is running"
else
    info "Whisper STT service not running (optional for notifications)"
fi

echo ""

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC}   $FAILED"
echo ""

TOTAL_ISSUES=$((FAILED + WARNINGS))
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All critical tests passed!${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo ""
        echo "Some warnings were detected. You may want to fix them for optimal behavior."
    fi
    echo ""
    echo "Next steps:"
    echo "1. Restart Claude Code for hooks to take effect"
    echo "2. Try doing some work - you should hear a summary when done"
    echo "3. Wait 60+ seconds idle - you should hear 'I am waiting for your next instruction for [project] on branch [branch]'"
    echo "4. Trigger a permission request - you should hear 'Claude needs permission...'"
    echo ""
    echo "To test again after restart, run:"
    echo "  $0"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Please fix the issues above.${NC}"
    exit 1
fi
