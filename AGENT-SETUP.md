# Global Setup Guide: Claude Code Voice Notifications

Step-by-step instructions for AI agents to set up voice notification hooks **globally** for all Claude Code projects.

> **Note:** This guide installs hooks globally in `~/.claude/`, so they work for every project automatically.

## Prerequisites

Before starting, verify:
- User is on macOS or Linux
- Python 3.10+ is installed (`python3 --version`)
- Claude Code CLI is installed
- User has permission to install system packages

## Overview

You will:
1. Install VoiceMode MCP server
2. Copy hook scripts to global Claude config (`~/.claude/hooks/`)
3. Merge hooks configuration into global settings.json
4. Run validation tests
5. Instruct user to restart Claude Code

## Step-by-Step Instructions

### Step 1: Verify Prerequisites

```bash
# Check OS
uname -s  # Should output "Darwin" (macOS) or "Linux"

# Check Python (3.10+)
python3 --version
```

### Step 2: Install VoiceMode

```bash
# Install uv package manager (if not installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install VoiceMode
uvx voice-mode-install

# Register VoiceMode with Claude Code
claude mcp add --scope user voicemode -- uvx --refresh voice-mode
```

**Verify VoiceMode is installed:**
```bash
claude mcp list | grep voicemode
```

### Step 3: Test VoiceMode

```bash
# Test voice output
voicemode converse -m "Voice notifications are ready" --no-wait
```

If you don't hear anything, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

### Step 4: Create Global Hooks Directory

```bash
# Create global hooks directory
mkdir -p ~/.claude/hooks
echo "Created: ~/.claude/hooks"
```

### Step 5: Create Hook Scripts

Create each script in `~/.claude/hooks/` with the exact content below.

#### 5.1: task-summary.sh

```bash
cat > ~/.claude/hooks/task-summary.sh << 'EOF'
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

#### 5.2: notification-idle.sh

```bash
cat > ~/.claude/hooks/notification-idle.sh << 'EOF'
#!/bin/bash
# Claude Code Hook: Notify when waiting for user input (idle)
# Triggered by Notification event with idle_prompt matcher after 60+ seconds

# Announce waiting for input via voicemode
voicemode converse -m "Claude is waiting for your input" --no-wait
EOF
```

#### 5.3: permission-request.sh

```bash
cat > ~/.claude/hooks/permission-request.sh << 'EOF'
#!/bin/bash
# Claude Code Hook: Notify when waiting for permission
# Triggered by PermissionRequest event when a permission dialog is shown

# Get tool info from stdin
INPUT=$(cat)

# Extract the tool name and description
TOOL=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('tool','unknown'))" 2>/dev/null)
DESC=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('description',''))" 2>/dev/null)

# Build message with description if available
if [ -n "$DESC" ]; then
    # Remove "Bash" prefix from description if present
    CLEAN_DESC=$(echo "$DESC" | sed 's/^Bash command //;s/^Bash //')
    MESSAGE="Claude is waiting to $CLEAN_DESC"
else
    MESSAGE="Claude is waiting to use $TOOL"
fi

# Announce permission request via voicemode
voicemode converse -m "$MESSAGE" --no-wait
EOF
```

#### 5.4: Make Scripts Executable

```bash
chmod +x ~/.claude/hooks/*.sh
echo "✓ Hook scripts created and made executable"
```

### Step 6: Create Global settings.json

**Check if settings.json already exists:**

```bash
if [ -f ~/.claude/settings.json ]; then
    echo "⚠ Existing ~/.claude/settings.json found"
    echo ""
    echo "Merging hooks configuration..."
    cat .claude/settings.json >> ~/.claude/settings.json
    echo "✓ Hooks merged into ~/.claude/settings.json"
else
    echo "Creating ~/.claude/settings.json..."
    cat > ~/.claude/settings.json << 'EOF'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/task-summary.sh"
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
            "command": "~/.claude/hooks/notification-idle.sh"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/permission-request.sh"
          }
        ]
      }
    ]
  }
}
EOF
    echo "✓ ~/.claude/settings.json created"
fi
```

### Step 7: Run Validation Tests

```bash
# Create test script
cat > ~/.claude/hooks/test-hooks.sh << 'TESTEOF'
#!/bin/bash
# Quick validation test for Claude Code voice notification hooks

HOOKS_DIR="$HOME/.claude/hooks"

echo "🔧 Claude Code Hooks Validation"
echo "================================"
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
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
if [ -f "$HOME/.claude/settings.json" ]; then
    if jq -e '.hooks.Stop' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
        pass "Stop hook registered"
    else
        fail "Stop hook not registered"
    fi
    if jq -e '.hooks.Notification[] | select(.matcher == "idle_prompt")' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
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

chmod +x ~/.claude/hooks/test-hooks.sh

# Run the test
~/.claude/hooks/test-hooks.sh
```

### Step 8: Final User Instructions

**Inform the user:**

```
✅ Voice notification hooks installed globally!

Files created:
- ~/.claude/hooks/task-summary.sh
- ~/.claude/hooks/notification-idle.sh
- ~/.claude/hooks/permission-request.sh
- ~/.claude/hooks/test-hooks.sh
- ~/.claude/settings.json (or merged)

What you'll hear:
• "Done: [task summary]" when tasks complete
• "Claude is waiting for your input" after 60 seconds idle
• "Claude is waiting to [action]" when permission is needed

Next steps:
1. Restart Claude Code completely (quit and reopen)
2. The hooks will now work for ALL projects automatically

To verify: ~/.claude/hooks/test-hooks.sh

To customize messages, edit the scripts in ~/.claude/hooks/
```

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for:
- Hooks not triggering
- No voice output
- VoiceMode installation issues
- settings.json conflicts

## Agent Checklist

- [ ] Verified OS and Python
- [ ] Installed VoiceMode and registered with Claude Code
- [ ] Tested VoiceMode voice output
- [ ] Created ~/.claude/hooks/ directory
- [ ] Created all three hook scripts
- [ ] Made scripts executable
- [ ] Created or merged ~/.claude/settings.json
- [ ] Validated installation with test script
- [ ] Provided restart instructions to user
