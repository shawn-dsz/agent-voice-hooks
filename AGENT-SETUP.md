# Agent Setup Guide: Claude Code Voice Notifications

Step-by-step instructions for AI agents to set up voice notification hooks for Claude Code in any repository.

## Prerequisites

Before starting, verify:
- User is on macOS (`uname -s` returns "Darwin`)
- Homebrew is installed (`command -v brew`)
- Claude Code CLI is installed
- User has permission to install system packages

## Overview

You will:
1. Install voicemode and dependencies
2. Install and start Kokoro TTS service
3. Copy hook scripts to the target project
4. Configure `settings.json` to register hooks
5. Run validation tests
6. Instruct user to restart Claude Code

## Step-by-Step Instructions

### Step 1: Verify Prerequisites

```bash
# Check macOS
uname -s  # Should output "Darwin"

# Check Homebrew
command -v brew || echo "Homebrew not installed"

# Check Python (3.10+)
python3 --version
```

**If Homebrew is missing**, inform the user:
> "You need Homebrew to install voicemode. Install it from https://brew.sh and run this setup again."

### Step 2: Get Target Project Path

Ask the user for their project path, or use current directory:

```bash
# If no path provided, use current directory
PROJECT_PATH="${1:-.}"

# Verify it's a valid directory
if [ ! -d "$PROJECT_PATH" ]; then
    echo "Error: $PROJECT_PATH is not a valid directory"
    exit 1
fi

cd "$PROJECT_PATH"
echo "Setting up voice hooks in: $(pwd)"
```

### Step 3: Install voicemode

```bash
# Check if already installed
if command -v voicemode >/dev/null 2>&1; then
    echo "✓ voicemode already installed"
    voicemode --version
else
    echo "Installing voicemode..."
    brew tap voicemode/voicemode
    brew install voicemode

    # Verify installation
    if voicemode --version >/dev/null 2>&1; then
        echo "✓ voicemode installed successfully"
    else
        echo "✗ voicemode installation failed"
        exit 1
    fi
fi
```

### Step 4: Start Kokoro TTS Service

```bash
# Check if service is running
if voicemode service status kokoro 2>/dev/null | grep -qi "running\|active"; then
    echo "✓ Kokoro TTS service already running"
else
    echo "Starting Kokoro TTS service..."
    voicemode service start kokoro

    # Wait a moment for service to start
    sleep 2

    # Verify it's running
    if voicemode service status kokoro 2>/dev/null | grep -qi "running\|active"; then
        echo "✓ Kokoro TTS service started"
    else
        echo "⚠ Kokoro service may not have started properly"
        echo "  You can start it manually with: voicemode service start kokoro"
    fi
fi
```

**Optional - Test TTS**:
```bash
echo "Testing voice output..."
voicemode converse -m "Voice notifications are ready" --no-wait
```

### Step 5: Create Hooks Directory Structure

```bash
# Create .claude/hooks directory
mkdir -p .claude/hooks
cd .claude/hooks
echo "Created: $(pwd)"
```

### Step 6: Create Hook Scripts

Create each script with the exact content below.

#### 6.1: task-summary.sh

```bash
cat > task-summary.sh << 'EOF'
#!/bin/bash
# Claude Code Stop Hook: Announce completed tasks summary
# Reads the most recent todo file and generates a ~10 word summary

TODO_DIR="$HOME/.claude/todos"

# Find the most recently modified todo file
LATEST_TODO=$(ls -t "$TODO_DIR"/*.json 2>/dev/null | head -1)

if [ -z "$LATEST_TODO" ]; then
    # No todo file found, use default message
    voicemode converse -m "Task completed. Ready for next instructions." --no-wait
    exit 0
fi

# Extract completed tasks from the todo file and generate summary
MESSAGE=$(python3 - "
import json

try:
    with open('$LATEST_TODO', 'r') as f:
        todos = json.load(f)

    completed = [t.get('content', '') for t in todos if t.get('status') == 'completed']

    if not completed:
        print('Task completed. Ready for next instructions.')
    elif len(completed) == 1:
        # Single task - use it directly, truncate to 8 words
        words = completed[0].split()
        if len(words) > 8:
            print('Done: ' + ' '.join(words[:8]) + '...')
        else:
            print('Done: ' + completed[0])
    else:
        # Multiple tasks - use the most recent (last in list)
        words = completed[-1].split()
        if len(words) > 8:
            print(f'Done: {len(completed)} tasks. Last: ' + ' '.join(words[:8]) + '...')
        else:
            print(f'Done: {len(completed)} tasks. Last: ' + completed[-1])
except Exception:
    print('Task completed. Ready for next instructions.')
" 2>/dev/null)

# Announce via voicemode
voicemode converse -m "$MESSAGE" --no-wait
EOF
```

#### 6.2: notification-idle.sh

```bash
cat > notification-idle.sh << 'EOF'
#!/bin/bash
# Claude Code Hook: Notify when waiting for user input (idle)
# Triggered by Notification event with idle_prompt matcher after 60+ seconds

# Announce waiting for input via voicemode
voicemode converse -m "Claude is waiting for your input" --no-wait
EOF
```

#### 6.3: permission-request.sh

```bash
cat > permission-request.sh << 'EOF'
#!/bin/bash
# Claude Code Hook: Notify when waiting for permission
# Triggered by PermissionRequest event when a permission dialog is shown

# Get tool info from stdin
INPUT=$(cat)

# Extract the tool name
TOOL=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('tool','unknown'))" 2>/dev/null)

# Announce permission request via voicemode
voicemode converse -m "Claude needs permission to use $TOOL" --no-wait
EOF
```

#### 6.4: Make Scripts Executable

```bash
chmod +x task-summary.sh notification-idle.sh permission-request.sh
echo "✓ Hook scripts created and made executable"
```

### Step 7: Handle settings.json

**IMPORTANT**: Check if settings.json already exists.

```bash
cd ..  # Go back to .claude directory

if [ -f settings.json ]; then
    echo "⚠ Existing settings.json found"
    echo ""
    echo "You need to merge the hooks configuration. The hooks to add are:"
    echo ""
    echo "1. Stop hook -> task-summary.sh"
    echo "2. Notification hook (idle_prompt) -> notification-idle.sh"
    echo "3. Notification hook (permission_prompt) -> permission-request.sh"
    echo ""
    echo "Add this to your settings.json:"
    echo ""
    cat << 'JSONEX'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/task-summary.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/notification-idle.sh"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/permission-request.sh"
          }
        ]
      }
    ]
  }
}
JSONEX
    echo ""
    echo "After merging, run: ./.claude/hooks/test-hooks.sh"
else
    # No existing settings.json - create new one
    echo "Creating settings.json..."
    cat > settings.json << 'EOF'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/task-summary.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/notification-idle.sh"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/permission-request.sh"
          }
        ]
      }
    ]
  }
}
EOF
    echo "✓ settings.json created"
fi
```

### Step 8: Run Validation Tests

```bash
cd hooks  # Back to hooks directory

# Create test script if it doesn't exist
if [ ! -f test-hooks.sh ]; then
    cat > test-hooks.sh << 'TESTEOF'
#!/bin/bash
# Quick validation test for Claude Code voice notification hooks

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_DIR="$PROJECT_DIR/.claude/hooks"

echo "🔧 Claude Code Hooks Validation"
echo "================================"
echo "Project: $PROJECT_DIR"
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() { echo -e "${GREEN}✓${NC} $1"; ((PASSED++)); }
fail() { echo -e "${RED}✗${NC} $1"; ((FAILED++)); }

# Test 1: Scripts exist
for script in task-summary.sh notification-idle.sh permission-request.sh; do
    if [ -x "$HOOKS_DIR/$script" ]; then
        pass "$script exists and executable"
    else
        fail "$script missing or not executable"
    fi
done

# Test 2: Settings.json
if [ -f "$PROJECT_DIR/.claude/settings.json" ]; then
    if jq -e '.hooks.Stop' "$PROJECT_DIR/.claude/settings.json" >/dev/null 2>&1; then
        pass "Stop hook registered"
    else
        fail "Stop hook not registered"
    fi
    if jq -e '.hooks.Notification[] | select(.matcher == "idle_prompt")' "$PROJECT_DIR/.claude/settings.json" >/dev/null 2>&1; then
        pass "Idle hook registered"
    else
        fail "Idle hook not registered"
    fi
else
    fail "settings.json not found"
fi

# Test 3: voicemode
if command -v voicemode >/dev/null 2>&1; then
    pass "voicemode installed"
else
    fail "voicemode not found"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some checks failed${NC}"
    exit 1
fi
TESTEOF

    chmod +x test-hooks.sh
fi

# Run the test
./test-hooks.sh
```

### Step 9: Final User Instructions

```bash
cd ../..  # Return to project root
```

**Inform the user**:

```
✅ Voice notification hooks installed!

Project: $PROJECT_PATH

Files created:
- .claude/hooks/task-summary.sh
- .claude/hooks/notification-idle.sh
- .claude/hooks/permission-request.sh
- .claude/hooks/test-hooks.sh
- .claude/settings.json (or merged)

Next steps:
1. Restart Claude Code completely
2. You'll hear voice announcements for:
   • Completed tasks
   • Idle state (after 60 seconds)
   • Permission requests

To verify: ./.claude/hooks/test-hooks.sh

To customize messages, edit the scripts in .claude/hooks/
```

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for:
- Hooks not triggering
- No voice output
- Kokoro service issues
- settings.json conflicts

## Agent Checklist

- [ ] Verified macOS and Homebrew
- [ ] Installed voicemode (or confirmed existing)
- [ ] Started Kokoro TTS service
- [ ] Created .claude/hooks/ directory
- [ ] Created all three hook scripts
- [ ] Made scripts executable
- [ ] Created or merged settings.json
- [ ] Validated installation with test script
- [ ] Provided restart instructions to user
